package top.helloswx.everyclass.widget

import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver

// 今日课表小组件的宿主 receiver。系统按 widget_today_info.xml 的 updatePeriodMillis
// 触发更新；更细的刷新（回桌面/上课时段/边界）由 WidgetRefresh 主动推送。
class TodayScheduleReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodayScheduleWidget()
}
