package top.helloswx.everyclass.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import java.util.Calendar

// 桌面卡片刷新调度（省电·免权限）：
//  · 主动刷新 —— 向两个 Glance receiver 发显式 ACTION_APPWIDGET_UPDATE 广播，触发
//    其 provideGlance 重读快照重绘。无需协程依赖。
//  · 边界兜底 —— 用 AlarmManager.set(RTC)（inexact、免 SCHEDULE_EXACT_ALARM）把下一次
//    刷新排到「今天下一个课程 start/end」；今日无更多边界则排到次日 00:05 跨天翻新。
// 调用方：MainActivity.onStop（回桌面即刷新，对齐鸿蒙 onBackground）、
//        ScheduleForegroundService 的分钟 tick（上课时段免费分钟级刷新）、WidgetTickReceiver。
object WidgetRefresh {
    const val ACTION_TICK = "top.helloswx.everyclass.widget.TICK"
    private const val REQUEST_CODE = 7301

    /** 立即刷新两张卡片，并把下一次刷新排到下一个课程边界。全程吞异常。 */
    fun requestUpdate(context: Context) {
        val app = context.applicationContext
        // 仅当桌面上确有卡片实例时才排边界闹钟：否则即便用户从未添加（或已移除全部）
        // 卡片，也会留下一个每到课程边界就经 WidgetTickReceiver 自我续期的闹钟空转。
        val pushedToday = runCatching { pushUpdate(app, TodayScheduleReceiver::class.java) }.getOrDefault(false)
        val pushedLive = runCatching { pushUpdate(app, LiveActivityReceiver::class.java) }.getOrDefault(false)
        if (pushedToday || pushedLive) runCatching { scheduleNextBoundary(app) }
    }

    /** 向某个 Glance receiver 推一次更新；桌面上没有它的实例则跳过。返回是否确有实例。 */
    private fun pushUpdate(context: Context, receiver: Class<*>): Boolean {
        val mgr = AppWidgetManager.getInstance(context) ?: return false
        val ids = mgr.getAppWidgetIds(ComponentName(context, receiver))
        if (ids == null || ids.isEmpty()) return false
        val intent = Intent(context, receiver).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(intent)
        return true
    }

    private fun scheduleNextBoundary(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val now = Calendar.getInstance()
        val nextMin = CardSnapshotReader.nextBoundaryMinuteOfDay(context, now)
        val triggerAt = if (nextMin != null) {
            atMinuteToday(now, nextMin) + 2_000L // +2s 缓冲，确保越过边界
        } else {
            nextDayAt(now, 0, 5) // 次日 00:05 跨天翻新
        }
        val pi = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            Intent(context, WidgetTickReceiver::class.java).setAction(ACTION_TICK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // 非唤醒 RTC：设备清醒时触发；息屏/Doze 延迟由 30 分钟系统周期与亮屏刷新兜底。
        am.set(AlarmManager.RTC, triggerAt, pi)
    }

    private fun atMinuteToday(now: Calendar, minuteOfDay: Int): Long {
        val c = now.clone() as Calendar
        c.set(Calendar.HOUR_OF_DAY, minuteOfDay / 60)
        c.set(Calendar.MINUTE, minuteOfDay % 60)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    private fun nextDayAt(now: Calendar, hour: Int, minute: Int): Long {
        val c = now.clone() as Calendar
        c.add(Calendar.DAY_OF_YEAR, 1)
        c.set(Calendar.HOUR_OF_DAY, hour)
        c.set(Calendar.MINUTE, minute)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }
}
