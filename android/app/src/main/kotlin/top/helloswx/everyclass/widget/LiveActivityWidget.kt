package top.helloswx.everyclass.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.action.actionStartActivity
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.width
import top.helloswx.everyclass.MainActivity

// 实时活动小组件：
//  2x2 —— 单一焦点（正在进行→当前课+距下课；否则→下一节+距上课）。
//  2x4 —— 左＝同 2x2 焦点，右＝今日课表主体（Header + 状态 + 可滚动列表）。
class LiveActivityWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, WIDE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val vm = CardSnapshotReader.load(context)
        provideContent { Content(vm) }
    }

    @Composable
    private fun Content(vm: CardVm) {
        val wide = LocalSize.current.width >= WIDE_THRESHOLD
        val root = GlanceModifier
            .fillMaxSize()
            .background(WidgetTheme.bg)
            .cornerRadius(16.dp)
            .padding(12.dp)
            .clickable(actionStartActivity<MainActivity>())
        if (wide) {
            Row(modifier = root) {
                FocusPane(
                    focus = vm.focus,
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                    verticalAlignment = Alignment.Top,
                    showNext = true,
                )
                Spacer(GlanceModifier.width(12.dp))
                TodayCardBody(
                    vm = vm,
                    wide = false,
                    showStatus = false,
                    modifier = GlanceModifier.defaultWeight().fillMaxHeight(),
                )
            }
        } else {
            FocusPane(focus = vm.focus, modifier = root)
        }
    }

    private companion object {
        val SMALL = DpSize(110.dp, 110.dp)
        val WIDE = DpSize(250.dp, 110.dp)
        val WIDE_THRESHOLD = 200.dp
    }
}
