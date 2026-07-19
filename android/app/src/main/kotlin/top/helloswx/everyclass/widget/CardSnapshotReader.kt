package top.helloswx.everyclass.widget

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.util.Calendar

// 桌面服务卡片的唯一数据源：读取 Flutter 侧写的 card_snapshot.json → 定位「今天」→
// 计算每节课状态、实时活动焦点、状态行文案。任何异常都退化为占位数据，保证卡片
// 始终有内容可渲染。
//
// 与 lib/platform/card_snapshot.dart（写）及鸿蒙 ohos/.../cardcommon/CardData.ets（读）
// 共享同一份契约；状态算法与 ScheduleForegroundService.computeState 对齐。

/** 一节课的展示态。 */
enum class LessonState { DONE, NOW, TODO }

/** 传给 UI 的单节课视图模型。 */
data class LessonVm(
    val subjectId: String,  // 所属课程 ID，供点课深链定位（可空字符串）
    val name: String,
    val room: String,
    val teacher: String,
    val startText: String,  // "08:00"
    val endText: String,    // "08:45"（自定义单一时刻可能为空）
    val startMinute: Int,   // 距零点分钟数，供点课深链定位（-1=未知）
    val periodText: String, // "第1节" / "第1-2节" / ""（自定义时刻）
    val colorHex: String,   // "#RRGGBB" / ""
    val state: LessonState,
)

/** 实时活动焦点模式。 */
enum class FocusMode { IN_CLASS, BEFORE_CLASS, ENDED, EMPTY }

/** 实时活动焦点：当前课或下一节 + 倒计时文案。 */
data class FocusVm(
    val mode: FocusMode,
    val phaseText: String,     // "正在进行" / "下一节" / "今天课程已结束 🎉" / "今日无课"
    val subject: String,       // 焦点科目（ENDED/EMPTY 为空）
    val room: String,
    val timeText: String,      // "08:00-08:45"
    val countdownText: String, // "距下课 23 分钟" / "距上课 5 分钟" / "即将上课" / ""
    val nextLabel: String = "", // 上课中且有下一节时："下一节 XX"；其余为空
)

/** 今日卡片整体视图模型。 */
data class CardVm(
    val title: String,       // 课表名，缺省「今日课程」
    val dateText: String,    // "7月19日 周六"
    val weekText: String,    // "第12周" / ""
    val statusText: String,  // 顶部状态行
    val hasData: Boolean,
    val lessons: List<LessonVm>,
    val focus: FocusVm,
)

object CardSnapshotReader {
    private const val SNAPSHOT_FILE = "card_snapshot.json"

    // Calendar.DAY_OF_WEEK：周日=1 … 周六=7，故按 (DAY_OF_WEEK-1) 取中文。
    private val WEEKDAY_CN = arrayOf("日", "一", "二", "三", "四", "五", "六")

    /** 读取快照并构建今日卡片视图模型。now 可注入以便测试/跨天验证。 */
    fun load(context: Context, now: Calendar = Calendar.getInstance()): CardVm {
        val dateText = "${now.get(Calendar.MONTH) + 1}月${now.get(Calendar.DAY_OF_MONTH)}日 " +
            "周${WEEKDAY_CN[(now.get(Calendar.DAY_OF_WEEK) - 1).coerceIn(0, 6)]}"
        val empty = CardVm(
            title = "今日课程",
            dateText = dateText,
            weekText = "",
            statusText = "打开应用创建课表",
            hasData = false,
            lessons = emptyList(),
            focus = FocusVm(FocusMode.EMPTY, "今日无课", "", "", "", ""),
        )

        val snap = readJson(context) ?: return empty
        val days = snap.optJSONArray("days") ?: return empty
        val todayKey = dateKey(now)
        var today: JSONObject? = null
        for (i in 0 until days.length()) {
            val d = days.optJSONObject(i) ?: continue
            if (d.optString("date") == todayKey) {
                today = d
                break
            }
        }

        val title = snap.optString("calendarName").ifBlank { "今日课程" }
        val weekText = today?.let {
            if (it.isNull("week")) "" else "第${it.optInt("week")}周"
        } ?: ""

        val lessonsRaw = today?.optJSONArray("lessons")
        if (today == null || lessonsRaw == null || lessonsRaw.length() == 0) {
            return empty.copy(
                title = title,
                weekText = weekText,
                statusText = "今日无课 🎉",
                focus = FocusVm(FocusMode.EMPTY, "今日无课", "", "", "", ""),
            )
        }

        val raws = ArrayList<RawLesson>(lessonsRaw.length())
        for (i in 0 until lessonsRaw.length()) {
            val o = lessonsRaw.optJSONObject(i) ?: continue
            raws.add(RawLesson.from(o))
        }
        // Dart 侧导出时已按 start 排序；保险再排一次。
        raws.sortBy { it.startMin }

        val nowMin = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        val lessons = ArrayList<LessonVm>(raws.size)
        var current: RawLesson? = null
        var next: RawLesson? = null
        for (r in raws) {
            val state = when {
                r.endMin >= 0 && nowMin >= r.endMin -> LessonState.DONE
                r.startMin in 0..nowMin && nowMin < r.endMin -> LessonState.NOW
                else -> LessonState.TODO
            }
            if (state == LessonState.NOW) current = r
            if (state == LessonState.TODO && next == null) next = r
            lessons.add(
                LessonVm(
                    subjectId = r.subjectId,
                    name = r.name,
                    room = r.room,
                    teacher = r.teacher,
                    startText = r.start,
                    endText = r.end,
                    startMinute = r.startMin,
                    periodText = periodText(r.startPeriod, r.endPeriod),
                    colorHex = r.color,
                    state = state,
                ),
            )
        }

        val focus = buildFocus(current, next, nowMin, hadLessons = raws.isNotEmpty())
        val statusText = when {
            current != null -> "正在进行 · ${current.name}"
            next != null -> "下一节 ${next.start} · ${next.name}"
            else -> "今天课程已结束 🎉"
        }

        // 默认置顶「当前活动」：未结束（正在进行 + 待上课，保持时序）在前，已结束的移到末尾。
        // Glance 的 LazyColumn 无滚动定位 API，故用重排近似「滚动到当前活动」。
        val ordered = lessons.filterNot { it.state == LessonState.DONE } +
            lessons.filter { it.state == LessonState.DONE }

        return CardVm(
            title = title,
            dateText = dateText,
            weekText = weekText,
            statusText = statusText,
            hasData = true,
            lessons = ordered,
            focus = focus,
        )
    }

    /** 今天在 now 之后的下一个课程边界（分钟-of-day）；无则 null。供刷新调度对齐边界。 */
    fun nextBoundaryMinuteOfDay(context: Context, now: Calendar = Calendar.getInstance()): Int? {
        val snap = readJson(context) ?: return null
        val days = snap.optJSONArray("days") ?: return null
        val todayKey = dateKey(now)
        var today: JSONObject? = null
        for (i in 0 until days.length()) {
            val d = days.optJSONObject(i) ?: continue
            if (d.optString("date") == todayKey) {
                today = d
                break
            }
        }
        val lessonsRaw = today?.optJSONArray("lessons") ?: return null
        val nowMin = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        var best: Int? = null
        for (i in 0 until lessonsRaw.length()) {
            val o = lessonsRaw.optJSONObject(i) ?: continue
            val s = minutesOf(o.optString("start"))
            val e = minutesOf(o.optString("end"))
            for (b in intArrayOf(s, e)) {
                if (b in (nowMin + 1)..1439 && (best == null || b < best!!)) best = b
            }
        }
        return best
    }

    private fun buildFocus(
        current: RawLesson?,
        next: RawLesson?,
        nowMin: Int,
        hadLessons: Boolean,
    ): FocusVm = when {
        current != null -> {
            val m = (current.endMin - nowMin).coerceAtLeast(0)
            FocusVm(
                mode = FocusMode.IN_CLASS,
                phaseText = "正在进行",
                subject = current.name,
                room = current.room,
                timeText = "${current.start}-${current.end}",
                countdownText = if (m <= 0) "即将下课" else "距下课 $m 分钟",
                nextLabel = if (next != null) "下一节 ${next.name}" else "",
            )
        }
        next != null -> {
            val m = (next.startMin - nowMin).coerceAtLeast(0)
            FocusVm(
                mode = FocusMode.BEFORE_CLASS,
                phaseText = "下一节",
                subject = next.name,
                room = next.room,
                timeText = "${next.start}-${next.end}",
                countdownText = if (m <= 0) "即将上课" else "距上课 $m 分钟",
            )
        }
        hadLessons -> FocusVm(FocusMode.ENDED, "今天课程已结束 🎉", "", "", "", "")
        else -> FocusVm(FocusMode.EMPTY, "今日无课", "", "", "", "")
    }

    private fun periodText(startPeriod: Int, endPeriod: Int): String = when {
        startPeriod <= 0 -> ""
        endPeriod > startPeriod -> "第$startPeriod-${endPeriod}节"
        else -> "第${startPeriod}节"
    }

    private fun readJson(context: Context): JSONObject? = try {
        // getApplicationDocumentsDirectory()（Dart）在 Android 上解析为
        // context.getDir("flutter", MODE_PRIVATE)（见 io.flutter.util.PathUtils）。
        val file = File(context.getDir("flutter", Context.MODE_PRIVATE), SNAPSHOT_FILE)
        if (!file.exists()) {
            null
        } else {
            val text = file.readText()
            if (text.isBlank()) null else JSONObject(text)
        }
    } catch (_: Exception) {
        null
    }

    private fun dateKey(c: Calendar): String =
        "%04d-%02d-%02d".format(
            c.get(Calendar.YEAR),
            c.get(Calendar.MONTH) + 1,
            c.get(Calendar.DAY_OF_MONTH),
        )

    /** "HH:mm" → 距零点分钟数；解析失败返回 -1。 */
    private fun minutesOf(hhmm: String): Int {
        val parts = hhmm.split(":")
        if (parts.size != 2) return -1
        val h = parts[0].toIntOrNull() ?: return -1
        val m = parts[1].toIntOrNull() ?: return -1
        return h * 60 + m
    }

    private data class RawLesson(
        val subjectId: String,
        val name: String,
        val room: String,
        val teacher: String,
        val start: String,
        val end: String,
        val startMin: Int,
        val endMin: Int,
        val startPeriod: Int,
        val endPeriod: Int,
        val color: String,
    ) {
        companion object {
            fun from(o: JSONObject): RawLesson {
                val start = o.optString("start")
                val end = o.optString("end")
                return RawLesson(
                    subjectId = o.optString("subjectId"),
                    name = o.optString("name"),
                    room = o.optString("room"),
                    teacher = o.optString("teacher"),
                    start = start,
                    end = end,
                    startMin = minutesOf(start),
                    endMin = minutesOf(end),
                    startPeriod = o.optInt("startPeriod"),
                    endPeriod = o.optInt("endPeriod"),
                    color = o.optString("color"),
                )
            }
        }
    }
}
