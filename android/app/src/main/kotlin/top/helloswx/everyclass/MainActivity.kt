package top.helloswx.everyclass

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import top.helloswx.everyclass.widget.LessonDeepLink
import top.helloswx.everyclass.widget.WidgetRefresh

class MainActivity : FlutterActivity() {
    private val notifChannel = "everyclass/live_notification"
    private val ioChannel = "everyclass/io"
    private val widgetChannel = "everyclass/widget"
    private val deeplinkChannelName = "everyclass/deeplink"
    private val reqPickJson = 42

    private var pendingPick: MethodChannel.Result? = null

    // 点课深链：冷启动时先把启动 Intent 解析暂存，等 Dart 侧 getInitialLesson 来取；
    // 应用已在前台时（onNewIntent）则直接经通道推给 Dart。
    private var deeplinkChannel: MethodChannel? = null
    private var pendingLesson: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notifChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(true)
                    "start" -> {
                        val rawLessons = call.argument<List<*>>("lessons")
                        if (rawLessons == null) {
                            result.error("invalid_arguments", "lessons 必须是数组", null)
                            return@setMethodCallHandler
                        }
                        val lessons = mutableListOf<Map<String, Any?>>()
                        for (rawLesson in rawLessons) {
                            val lesson = rawLesson as? Map<*, *>
                            val subject = (lesson?.get("subject") as? String)?.trim()
                            val room = (lesson?.get("room") as? String)?.trim()
                            val teacher = (lesson?.get("teacher") as? String)?.trim()
                            val period = lesson?.get("period") as? Number
                            val startMs = lesson?.get("startMs") as? Number
                            val endMs = lesson?.get("endMs") as? Number
                            if (subject.isNullOrEmpty() || room == null || teacher == null ||
                                period == null || startMs == null || endMs == null ||
                                endMs.toLong() <= startMs.toLong()
                            ) {
                                result.error("invalid_arguments", "课程字段不完整或时间区间无效", null)
                                return@setMethodCallHandler
                            }
                            lessons += mapOf(
                                "subject" to subject,
                                "room" to room,
                                "teacher" to teacher,
                                "period" to period.toInt(),
                                "startMs" to startMs.toLong(),
                                "endMs" to endMs.toLong(),
                            )
                        }
                        ensureNotificationPermission()
                        val enhanced = call.argument<Boolean>("enhancedCountdown") ?: false
                        val intent = Intent(this, ScheduleForegroundService::class.java).apply {
                            action = ScheduleForegroundService.ACTION_START
                            putExtra(ScheduleForegroundService.EXTRA_LESSONS, lessonsToJson(lessons))
                            putExtra(ScheduleForegroundService.EXTRA_ENHANCED, enhanced)
                            putExtra(
                                ScheduleForegroundService.EXTRA_REMIND_BEFORE,
                                call.argument<Boolean>("remindBefore") ?: false,
                            )
                            putExtra(
                                ScheduleForegroundService.EXTRA_REMIND_START,
                                call.argument<Boolean>("remindStart") ?: false,
                            )
                            putExtra(
                                ScheduleForegroundService.EXTRA_REMIND_END,
                                call.argument<Boolean>("remindEnd") ?: false,
                            )
                            putExtra(
                                ScheduleForegroundService.EXTRA_REMIND_LEAD_SEC,
                                call.argument<Int>("remindLeadSeconds") ?: 300,
                            )
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(true)
                    }
                    "update" -> {
                        val subject = call.argument<String>("subject")?.trim()
                        val room = call.argument<String>("room")?.trim()
                        val teacher = call.argument<String>("teacher")?.trim()
                        val phase = call.argument<String>("phase")?.trim()
                        val statusLabel = call.argument<String>("statusLabel")?.trim()
                        val startEpochMs = call.argument<Number>("countdownStartEpochMs")?.toLong()
                        val endEpochMs = call.argument<Number>("countdownEndEpochMs")?.toLong()
                        if (subject.isNullOrEmpty() || room == null || teacher == null ||
                            phase.isNullOrEmpty() || statusLabel.isNullOrEmpty() ||
                            startEpochMs == null || endEpochMs == null || endEpochMs <= startEpochMs
                        ) {
                            result.error("invalid_arguments", "实时通知展示状态不完整或时间区间无效", null)
                            return@setMethodCallHandler
                        }
                        ensureNotificationPermission()
                        val intent = Intent(this, ScheduleForegroundService::class.java).apply {
                            action = ScheduleForegroundService.ACTION_UPDATE
                            putExtra(ScheduleForegroundService.EXTRA_SUBJECT, subject)
                            putExtra(ScheduleForegroundService.EXTRA_ROOM, room)
                            putExtra(ScheduleForegroundService.EXTRA_TEACHER, teacher)
                            putExtra(ScheduleForegroundService.EXTRA_PHASE, phase)
                            putExtra(ScheduleForegroundService.EXTRA_STATUS_LABEL, statusLabel)
                            putExtra(ScheduleForegroundService.EXTRA_COUNTDOWN_START, startEpochMs)
                            putExtra(ScheduleForegroundService.EXTRA_COUNTDOWN_END, endEpochMs)
                        }
                        ContextCompat.startForegroundService(this, intent)
                        result.success(true)
                    }
                    "stop" -> {
                        val intent = Intent(this, ScheduleForegroundService::class.java).apply {
                            action = ScheduleForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ioChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickJson" -> {
                        if (pendingPick != null) {
                            result.error("busy", "已有一个选择中的文件", null)
                            return@setMethodCallHandler
                        }
                        pendingPick = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            // 部分文件管理器不把 .json 标为 application/json，用 */* 更稳。
                            type = "*/*"
                        }
                        startActivityForResult(intent, reqPickJson)
                    }
                    else -> result.notImplemented()
                }
            }

        // Dart 侧写完 card_snapshot.json 后调用，立即重绘桌面卡片——不必等回桌面
        // （onStop）或前台服务的分钟 tick，改动课程即时生效。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        runCatching { WidgetRefresh.requestUpdate(this) }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // 点课深链：解析启动 Intent 暂存；Dart 侧启动后调 getInitialLesson 取一次
        // （冷启动路径）。应用已在前台时改由 onNewIntent 直接推 openLesson。
        pendingLesson = parseLessonIntent(intent)
        deeplinkChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deeplinkChannelName).also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "getInitialLesson" -> {
                            result.success(pendingLesson)
                            pendingLesson = null
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val lesson = parseLessonIntent(intent) ?: return
        val ch = deeplinkChannel
        if (ch != null) {
            ch.invokeMethod("openLesson", lesson)
        } else {
            // 引擎/通道尚未就绪（极少见）：暂存，等 getInitialLesson 兜底。
            pendingLesson = lesson
        }
    }

    /** 从 OPEN_LESSON Intent 提取课程身份；非点课深链返回 null。 */
    private fun parseLessonIntent(intent: Intent?): Map<String, Any?>? {
        if (intent == null || intent.action != LessonDeepLink.ACTION) return null
        val sid = intent.getStringExtra(LessonDeepLink.EXTRA_SUBJECT_ID) ?: ""
        val start = intent.getIntExtra(LessonDeepLink.EXTRA_START_MINUTE, -1)
        if (sid.isEmpty() && start < 0) return null
        return mapOf("subjectId" to sid, "startMinute" to start)
    }

    override fun onStop() {
        super.onStop()
        // 回到桌面时用最新快照刷新桌面服务卡片（对齐鸿蒙 EntryAbility.onBackground）。
        runCatching { WidgetRefresh.requestUpdate(this) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqPickJson) return
        val result = pendingPick
        pendingPick = null
        val uri = data?.data
        if (resultCode == RESULT_OK && uri != null) {
            try {
                val text = contentResolver.openInputStream(uri)
                    ?.bufferedReader()
                    ?.use { it.readText() }
                result?.success(text)
            } catch (e: Exception) {
                result?.error("read_failed", e.message, null)
            }
        } else {
            result?.success(null) // 用户取消
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                1001,
            )
        }
    }

    private fun lessonsToJson(lessons: List<Map<String, Any?>>?): String {
        val arr = JSONArray()
        lessons?.forEach { m ->
            arr.put(
                JSONObject().apply {
                    put("subject", m["subject"] ?: "")
                    put("room", m["room"] ?: "")
                    put("teacher", m["teacher"] ?: "")
                    put("period", (m["period"] as? Number)?.toInt() ?: 0)
                    put("startMs", (m["startMs"] as? Number)?.toLong() ?: 0L)
                    put("endMs", (m["endMs"] as? Number)?.toLong() ?: 0L)
                },
            )
        }
        return arr.toString()
    }
}
