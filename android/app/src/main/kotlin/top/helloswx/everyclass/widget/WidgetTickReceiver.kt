package top.helloswx.everyclass.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// 边界闹钟接收器：AlarmManager 到点后刷新卡片并排下一次。仅处理显式 ACTION_TICK。
class WidgetTickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == WidgetRefresh.ACTION_TICK) {
            WidgetRefresh.requestUpdate(context)
        }
    }
}
