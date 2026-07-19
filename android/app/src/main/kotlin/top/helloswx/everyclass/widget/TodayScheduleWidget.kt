package top.helloswx.everyclass.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import top.helloswx.everyclass.MainActivity

// 今日课表小组件：2x2 / 2x4 同一套结构（Header + 状态行 + 可滚动课程列表），
// 越宽/越高可见行越多、副信息更全。数据来自 CardSnapshotReader。
class TodayScheduleWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, WIDE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val vm = CardSnapshotReader.load(context)
        provideContent { Content(vm) }
    }

    @Composable
    private fun Content(vm: CardVm) {
        val wide = LocalSize.current.width >= WIDE_THRESHOLD
        TodayCardBody(
            vm = vm,
            wide = wide,
            modifier = GlanceModifier
                .fillMaxSize()
                .background(WidgetTheme.bg)
                .cornerRadius(16.dp)
                .padding(12.dp)
                .clickable(actionStartActivity<MainActivity>()),
        )
    }

    private companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val WIDE = DpSize(250.dp, 110.dp)
        val WIDE_THRESHOLD = 200.dp
    }
}
