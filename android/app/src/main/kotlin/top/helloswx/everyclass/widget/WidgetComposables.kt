package top.helloswx.everyclass.widget

import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import top.helloswx.everyclass.MainActivity
import top.helloswx.everyclass.R

// 两张卡片共享的 Glance 组合函数。纯展示；数据来自 CardSnapshotReader。

/** 顶部：左＝日期 + 周次，右＝课表名。 */
@Composable
fun HeaderRow(vm: CardVm) {
    Row(modifier = GlanceModifier.fillMaxWidth()) {
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = vm.dateText,
                style = TextStyle(
                    color = WidgetTheme.textPrimary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
            if (vm.weekText.isNotEmpty()) {
                Text(
                    text = vm.weekText,
                    style = TextStyle(color = WidgetTheme.textSecondary, fontSize = 10.sp),
                    maxLines = 1,
                )
            }
        }
        Text(
            text = vm.title,
            style = TextStyle(color = WidgetTheme.textSecondary, fontSize = 10.sp),
            maxLines = 1,
        )
    }
}

/** 状态行：正在上课 / 下一节 / 已结束。 */
@Composable
fun StatusText(text: String) {
    Text(
        text = text,
        style = TextStyle(color = WidgetTheme.accent, fontSize = 11.sp),
        maxLines = 1,
        modifier = GlanceModifier.fillMaxWidth().padding(top = 4.dp, bottom = 6.dp),
    )
}

/** 单节课行：整高色条 + 名/副信息 + 起止时间；now 圆角高亮，done 降为次要色并整体收缩、字号减小以弱化存在感。
 *  外层 Box 只提供行间距；内层定高 Row 承载 now 背景，让色条经 fillMaxHeight 填满整行
 *  （Glance 里 fillMaxHeight 需父级定高才生效，LazyColumn item 高度默认不受限）。色条左缘
 *  与背景圆角齐平：用 tint 后的左圆角 shape（widget_lesson_bar），右缘直角紧贴内容。 */
@Composable
fun LessonRow(l: LessonVm, wide: Boolean) {
    val isNow = l.state == LessonState.NOW
    val isDone = l.state == LessonState.DONE
    // 已结束课程色：day/night 分别调校（深色模式白字观感更亮，用更低不透明度维持“弱化”）。
    // 必须走 day/night ColorProvider 而非资源色：Glance 的 ColorFilter.tint 不解析资源色的
    // 明暗变体（只取默认/浅色值），否则色条在深色模式下会用错颜色（浅色值贴到深色底上）。
    val doneColor = androidx.glance.color.ColorProvider(
        day = Color(0x8A000000),
        night = Color(0x73FFFFFF),
    )
    val nameColor = if (isDone) doneColor else WidgetTheme.textPrimary
    val subColor = if (isDone) doneColor else WidgetTheme.textSecondary

    // 已结束的课：更矮的行 + 更小的字号，进一步弱化存在感（色条已是次要色、且随行收短）。
    val rowHeight = if (isDone) (if (wide) 32.dp else 30.dp) else (if (wide) 38.dp else 36.dp)
    val nameSize = if (isDone) 11.sp else 13.sp
    val subSize = if (isDone) 9.sp else 10.sp

    val rowModifier = GlanceModifier.fillMaxWidth().height(rowHeight)
        .background(ImageProvider(if (isNow) R.drawable.widget_now_bg else R.drawable.widget_row_bg))

    // 点这行课→显式启动 MainActivity（OPEN_LESSON），带上课程 ID 与起始分钟，
    // 由应用侧定位这节课并唤出详情浮窗。data 逐课唯一，保证各行 PendingIntent 不串。
    val ctx = LocalContext.current
    val openIntent = Intent(ctx, MainActivity::class.java).apply {
        action = LessonDeepLink.ACTION
        data = Uri.parse(
            "${LessonDeepLink.SCHEME}://lesson/${Uri.encode(l.subjectId)}/${l.startMinute}",
        )
        putExtra(LessonDeepLink.EXTRA_SUBJECT_ID, l.subjectId)
        putExtra(LessonDeepLink.EXTRA_START_MINUTE, l.startMinute)
    }

    Box(
        modifier = GlanceModifier.fillMaxWidth().padding(vertical = 2.dp)
            .clickable(actionStartActivity(openIntent)),
    ) {
        Row(modifier = rowModifier, verticalAlignment = Alignment.CenterVertically) {
            Image(
                provider = ImageProvider(R.drawable.widget_lesson_bar),
                contentDescription = null,
                contentScale = ContentScale.FillBounds,
                colorFilter = ColorFilter.tint(if (isDone) doneColor else barColor(l.colorHex)),
                modifier = GlanceModifier.width(if (wide) 10.dp else 8.dp).fillMaxHeight(),
            )
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = l.name,
                    style = TextStyle(
                        color = nameColor,
                        fontSize = nameSize,
                        fontWeight = FontWeight.Medium,
                    ),
                    maxLines = 1,
                )
                val sub = buildSub(l, wide)
                if (sub.isNotEmpty()) {
                    Text(
                        text = sub,
                        style = TextStyle(color = subColor, fontSize = subSize),
                        maxLines = 1,
                    )
                }
            }
            Spacer(GlanceModifier.width(6.dp))
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = l.startText,
                    style = TextStyle(color = subColor, fontSize = subSize),
                    maxLines = 1,
                )
                if (l.endText.isNotBlank()) {
                    Text(
                        text = l.endText,
                        style = TextStyle(color = subColor, fontSize = subSize),
                        maxLines = 1,
                    )
                }
            }
            Spacer(GlanceModifier.width(8.dp))
        }
    }
}

/** 今日课程列表（可滚动）；空则居中占位。sizing 由调用方经 modifier 决定
 *  （通常传 defaultWeight().fillMaxWidth() 以占满剩余空间）。 */
@Composable
fun TodayList(lessons: List<LessonVm>, wide: Boolean, modifier: GlanceModifier = GlanceModifier) {
    if (lessons.isEmpty()) {
        Box(modifier = modifier, contentAlignment = Alignment.Center) {
            Text(
                text = (if (wide) "今天没有课程" else "今日无课") + " 🎉",
                style = TextStyle(color = WidgetTheme.textSecondary, fontSize = 13.sp),
                maxLines = 1,
            )
        }
        return
    }
    LazyColumn(modifier = modifier) {
        items(lessons) { l -> LessonRow(l, wide) }
    }
}

/** 今日课表卡片主体：Header + 状态行 + 可滚动列表。今日课表卡片与实时活动 2x4
 *  右栏共用。sizing 由 modifier 决定（通常 fillMaxSize 或 defaultWeight().fillMaxHeight）。 */
@Composable
fun TodayCardBody(
    vm: CardVm,
    wide: Boolean,
    showStatus: Boolean = true,
    modifier: GlanceModifier = GlanceModifier,
) {
    Column(modifier = modifier) {
        HeaderRow(vm)
        if (showStatus) StatusText(vm.statusText) else Spacer(GlanceModifier.height(8.dp))
        TodayList(
            lessons = vm.lessons,
            wide = wide,
            modifier = GlanceModifier.defaultWeight().fillMaxWidth(),
        )
    }
}

/** 实时活动焦点面板：状态 + 大字科目 + 教室 + 倒计时。
 *  showNext 时（宽版 2x4 左栏），上课中若有下一节，底端追加「下一节 XX」：
 *  主体压顶 + 加权 Spacer 把提示推到底部实现低端对齐。 */
@Composable
fun FocusPane(
    focus: FocusVm,
    modifier: GlanceModifier = GlanceModifier,
    verticalAlignment: Alignment.Vertical = Alignment.CenterVertically,
    showNext: Boolean = false,
) {
    val nextLine = showNext && focus.nextLabel.isNotEmpty()
    Column(
        modifier = modifier,
        verticalAlignment = if (nextLine) Alignment.Top else verticalAlignment,
    ) {
        Text(
            text = focus.phaseText,
            style = TextStyle(
                color = WidgetTheme.accent,
                fontSize = focusPhaseSize(focus.phaseText),
                fontWeight = FontWeight.Medium,
            ),
            maxLines = 1,
        )
        if (focus.subject.isNotEmpty()) {
            Spacer(GlanceModifier.height(4.dp))
            Text(
                text = focus.subject,
                style = TextStyle(
                    color = WidgetTheme.textPrimary,
                    fontSize = focusSubjectSize(focus.subject),
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 2,
            )
        }
        if (focus.room.isNotEmpty()) {
            Spacer(GlanceModifier.height(2.dp))
            Text(
                text = focus.room,
                style = TextStyle(color = WidgetTheme.textSecondary, fontSize = 12.sp),
                maxLines = 1,
            )
        }
        val tail = focus.countdownText.ifEmpty { focus.timeText }
        if (tail.isNotEmpty()) {
            Spacer(GlanceModifier.height(6.dp))
            Text(
                text = tail,
                style = TextStyle(
                    color = if (focus.countdownText.isNotEmpty()) WidgetTheme.accent else WidgetTheme.textSecondary,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
        }
        if (nextLine) {
            Spacer(GlanceModifier.defaultWeight())
            Text(
                text = focus.nextLabel,
                style = TextStyle(
                    color = WidgetTheme.textSecondary,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                ),
                maxLines = 1,
            )
        }
    }
}

/** 焦点科目字号：Glance 无原生 autosize，按名称长度分档——短名更大、长名收缩以避免截断。 */
private fun focusSubjectSize(subject: String): TextUnit = when {
    subject.length <= 4 -> 24.sp
    subject.length <= 6 -> 20.sp
    subject.length <= 8 -> 17.sp
    else -> 15.sp
}

/** 焦点状态字号：短状态（正在进行/下一节）放大更醒目；长状态（今天课程已结束 🎉）逐级收窄避免 2x2 截断。 */
private fun focusPhaseSize(phase: String): TextUnit = when {
    phase.length <= 4 -> 15.sp
    phase.length <= 5 -> 13.sp
    phase.length <= 7 -> 11.sp
    else -> 10.sp
}

private fun buildSub(l: LessonVm, wide: Boolean): String {
    val parts = ArrayList<String>(3)
    if (l.room.isNotBlank()) parts.add(l.room)
    if (wide && l.teacher.isNotBlank()) parts.add(l.teacher)
    if (wide && l.periodText.isNotBlank()) parts.add(l.periodText)
    return parts.joinToString(" · ")
}

/** 未结束课程的色条颜色：解析 "#RRGGBB"（应用内已写入解析后的课程色），失败回退强调色。
 *  回退也走 day/night：Glance tint 不解析资源色的明暗（见 LessonRow doneColor 注释）。 */
private fun barColor(hex: String): ColorProvider {
    val parsed = runCatching { Color(android.graphics.Color.parseColor(hex)) }.getOrNull()
    if (parsed != null) return ColorProvider(parsed)
    return androidx.glance.color.ColorProvider(day = Color(0xFF3F51B5), night = Color(0xFF9FA8DA))
}
