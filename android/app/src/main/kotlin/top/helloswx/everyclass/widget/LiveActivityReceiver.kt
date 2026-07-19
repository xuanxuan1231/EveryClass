package top.helloswx.everyclass.widget

import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver

// 实时活动小组件的宿主 receiver。刷新由 WidgetRefresh 主动推送 + 系统周期兜底。
class LiveActivityReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = LiveActivityWidget()
}
