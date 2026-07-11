package com.example.everyclass

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import java.util.Calendar

/**
 * 常驻前台服务：持有今日课表，在每节课边界刷新一条实时通知，显示当前/下一节课的
 * 课程名、时间、教室，并带系统原生倒计时。
 *
 * - Android 16+（API 36）：使用 [Notification.ProgressStyle] + [Notification.FLAG_PROMOTED_ONGOING]
 *   呈现 Live Update（含指向下课的进度条）。
 * - 低版本：回退到 [NotificationCompat] 常驻通知 + Chronometer 倒计时 + 进度条。
 *
 * 课表数据由 Flutter 通过 MethodChannel 下发（见 MainActivity），并持久化以便进程被
 * 系统重启（START_STICKY，null intent）后当天仍能恢复。
 */
class ScheduleForegroundService : Service() {

    companion object {
        const val ACTION_START = "everyclass.action.START"
        const val ACTION_STOP = "everyclass.action.STOP"
        const val EXTRA_LESSONS = "lessons"
        const val EXTRA_ENHANCED = "enhanced"

        private const val CHANNEL_ID = "everyclass_live"
        private const val NOTIF_ID = 1001
        private const val PREFS = "everyclass_fgs"
        private const val KEY_LESSONS = "lessons_json"
        private const val KEY_BASE = "lessons_base"
        private const val KEY_ENHANCED = "enhanced"
        private const val ACCENT = 0xFF3F51B5.toInt()
        private const val TICK_INTERVAL_MS = 60_000L
    }

    private data class Lesson(
        val subject: String,
        val room: String,
        val teacher: String,
        val period: Int,
        val startMs: Long,
        val endMs: Long,
    )

    private data class NState(
        val title: String,
        val text: String,
        val chipText: String,
        val whenTarget: Long,
        val countUp: Boolean,
        val segTotalSec: Int,
        val segElapsedSec: Int,
        val iconRes: Int,
        val done: Boolean,
    )

    private val handler = Handler(Looper.getMainLooper())
    private val ticker = Runnable { tick() }
    private var lessons: List<Lesson> = emptyList()
    private var enhanced = false

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTicking()
                stopForegroundCompat(remove = true)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val json = intent.getStringExtra(EXTRA_LESSONS)
                enhanced = intent.getBooleanExtra(EXTRA_ENHANCED, false)
                saveLessons(json)
                lessons = parse(json)
                startCycle()
            }
            else -> {
                // 进程被系统重启（null intent）：从持久化恢复今日课表与设置。
                lessons = parse(loadLessons())
                enhanced = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getBoolean(KEY_ENHANCED, false)
                startCycle()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopTicking()
        super.onDestroy()
    }

    private fun startCycle() {
        val state = computeState()
        // 必须在 5 秒内前台化，否则会 ANR。
        startForegroundWith(buildNotification(state))
        afterPost(state)
    }

    private fun tick() {
        val state = computeState()
        notificationManager().notify(NOTIF_ID, buildNotification(state))
        afterPost(state)
    }

    private fun afterPost(state: NState) {
        if (state.done) {
            stopTicking()
            // 今日结束/无课：保留这条（可清除）通知，并结束前台状态。
            stopForegroundCompat(remove = false)
            stopSelf()
        } else {
            scheduleNextTick()
        }
    }

    private fun scheduleNextTick() {
        stopTicking()
        val now = System.currentTimeMillis()
        var nextBoundary = Long.MAX_VALUE
        for (l in lessons) {
            if (l.startMs > now) nextBoundary = minOf(nextBoundary, l.startMs)
            if (l.endMs > now) nextBoundary = minOf(nextBoundary, l.endMs)
        }
        if (nextBoundary == Long.MAX_VALUE) return
        // 逐秒模式每秒刷新（驱动 chip 跳秒，因 shortCriticalText 是静态文本）；否则每分钟。
        val interval = if (enhanced) 1_000L else TICK_INTERVAL_MS
        val delay = minOf(nextBoundary - now, interval).coerceIn(1_000L, interval)
        handler.postDelayed(ticker, delay)
    }

    private fun stopTicking() = handler.removeCallbacks(ticker)

    // ---- 状态 ----

    private fun computeState(): NState {
        val now = System.currentTimeMillis()
        val cur = lessons.firstOrNull { now >= it.startMs && now < it.endMs }
        val nxt = lessons.firstOrNull { it.startMs > now }
        return when {
            cur != null -> {
                val total = ((cur.endMs - cur.startMs) / 1000).toInt().coerceAtLeast(1)
                NState(
                    title = cur.subject,
                    text = line(cur.room, "${fmt(cur.startMs)}-${fmt(cur.endMs)}"),
                    // 上课中：负号。逐秒=负 M:SS，每分钟=负 Nm
                    chipText = if (enhanced) "-${fmtClock(cur.endMs - now)}"
                    else "-${minutesUntil(cur.endMs, now)}m",
                    whenTarget = cur.endMs,
                    countUp = true,
                    segTotalSec = total,
                    segElapsedSec = ((now - cur.startMs) / 1000).toInt().coerceIn(0, total),
                    iconRes = R.drawable.ic_stat_class, // 上课中
                    done = false,
                )
            }
            nxt != null -> {
                // 课间/课前：进度指向下一节开始，使 ProgressStyle 全程存在。
                val prevEnd = lessons.filter { it.endMs <= now }.maxOfOrNull { it.endMs }
                val anchor = prevEnd ?: (nxt.startMs - 3_600_000L) // 无前节则取前 1 小时窗口
                val total = ((nxt.startMs - anchor) / 1000).toInt().coerceAtLeast(1)
                val soon = nxt.startMs - now <= 60_000L // 上课前 1 分钟
                NState(
                    title = nxt.subject,
                    text = line(nxt.room, "${fmt(nxt.startMs)}-${fmt(nxt.endMs)}"),
                    // 下一节：正号。逐秒=M:SS，每分钟=Nm
                    chipText = if (enhanced) fmtClock(nxt.startMs - now)
                    else "${minutesUntil(nxt.startMs, now)}m",
                    whenTarget = nxt.startMs,
                    countUp = false,
                    segTotalSec = total,
                    segElapsedSec = ((now - anchor) / 1000).toInt().coerceIn(0, total),
                    iconRes = if (soon) R.drawable.ic_stat_soon else R.drawable.ic_stat_idle,
                    done = false,
                )
            }
            else -> NState(
                title = if (lessons.isEmpty()) "今日无课" else "今日课程已结束",
                text = if (lessons.isEmpty()) "" else "明天见 👋",
                chipText = "",
                whenTarget = 0,
                countUp = false,
                segTotalSec = 0,
                segElapsedSec = 0,
                iconRes = R.drawable.ic_stat_idle,
                done = true,
            )
        }
    }

    private fun line(room: String, time: String): String =
        if (room.isBlank()) time else "$time · $room"

    /** 距 [target] 还有几分钟（向上取整，最小 0）。 */
    private fun minutesUntil(target: Long, now: Long): Int =
        (((target - now) + 59_999L) / 60_000L).toInt().coerceAtLeast(0)

    /** 毫秒时长 → 时钟文本：>1h 显示 H:MM:SS，否则 M:SS。 */
    private fun fmtClock(ms: Long): String {
        val totalSec = (ms / 1000).coerceAtLeast(0)
        val h = totalSec / 3600
        val m = (totalSec % 3600) / 60
        val s = totalSec % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
    }

    // ---- 通知构建 ----

    private fun buildNotification(state: NState): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        // 官方 Live Updates 要求（Android 16+ 提升为实时更新；低版本经 NotificationCompat
        // 自动降级为普通常驻通知）：
        //  · 标准样式（此处 ProgressStyle）      · setRequestPromotedOngoing 请求提升
        //  · ongoing（FLAG_ONGOING_EVENT）        · 必须有 contentTitle
        //  · 无自定义 RemoteViews                 · 不得 setColorized(true)
        //  · 渠道非 IMPORTANCE_MIN                · manifest 声明 POST_PROMOTED_NOTIFICATIONS
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(state.iconRes)
            .setContentTitle(state.title)
            .setContentText(state.text)
            .setOngoing(!state.done)
            .setOnlyAlertOnce(true)
            .setColor(ACCENT) // 仅强调色；不可 setColorized(true)，否则不被提升
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(contentIntent)
            .setRequestPromotedOngoing(!state.done)

        // 岛/常驻条只显示"带符号时间"（不显示科目）。逐秒由服务每秒重发驱动，
        // 因为 chip 的 shortCriticalText 是静态文本、系统不会自动跳秒。
        if (state.chipText.isNotEmpty()) {
            builder.setShortCriticalText(state.chipText)
        }
        // 展开态原生跳秒计时（下一节倒计时→正 / 上课中正计时到下课→负）。
        if (state.whenTarget > 0) {
            builder.setShowWhen(true)
                .setWhen(state.whenTarget)
                .setUsesChronometer(true)
                .setChronometerCountDown(!state.countUp)
        }
        if (state.segTotalSec > 0) {
            builder.setStyle(
                NotificationCompat.ProgressStyle()
                    .addProgressSegment(
                        NotificationCompat.ProgressStyle.Segment(state.segTotalSec)
                            .setColor(ACCENT),
                    )
                    .setProgress(state.segElapsedSec.coerceIn(0, state.segTotalSec)),
            )
        }
        return builder.build()
    }

    private fun createChannel() {
        val ch = NotificationChannel(
            CHANNEL_ID,
            "课程实时通知",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "在锁屏/状态栏显示当前与下一节课"
            setShowBadge(false)
        }
        notificationManager().createNotificationChannel(ch)
    }

    private fun startForegroundWith(n: Notification) {
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun stopForegroundCompat(remove: Boolean) {
        stopForeground(if (remove) STOP_FOREGROUND_REMOVE else STOP_FOREGROUND_DETACH)
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    // ---- 解析 & 持久化 ----

    private fun parse(json: String?): List<Lesson> {
        if (json.isNullOrEmpty()) return emptyList()
        return try {
            val base = startOfToday()
            val arr = JSONArray(json)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                Lesson(
                    subject = o.optString("subject"),
                    room = o.optString("room"),
                    teacher = o.optString("teacher"),
                    period = o.optInt("period"),
                    // startMs/endMs 是"距零点的毫秒"，加今天零点得到绝对时刻。
                    startMs = base + o.optLong("startMs"),
                    endMs = base + o.optLong("endMs"),
                )
            }.sortedBy { it.startMs }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun startOfToday(): Long {
        val c = Calendar.getInstance()
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    private fun fmt(ms: Long): String {
        val c = Calendar.getInstance().apply { timeInMillis = ms }
        return "%02d:%02d".format(c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE))
    }

    private fun saveLessons(json: String?) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(KEY_LESSONS, json ?: "")
            .putLong(KEY_BASE, startOfToday())
            .putBoolean(KEY_ENHANCED, enhanced)
            .apply()
    }

    /** 仅当持久化数据属于"今天"时才恢复，避免跨天显示过期课表。 */
    private fun loadLessons(): String? {
        val p = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (p.getLong(KEY_BASE, -1L) != startOfToday()) return null
        return p.getString(KEY_LESSONS, null)
    }
}
