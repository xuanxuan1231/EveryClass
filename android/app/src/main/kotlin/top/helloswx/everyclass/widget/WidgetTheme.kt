package top.helloswx.everyclass.widget

import androidx.glance.unit.ColorProvider
import top.helloswx.everyclass.R

// 卡片配色：用资源型 ColorProvider（自动明暗，取 res/values 与 res/values-night 的
// colors.xml）。镜像鸿蒙 color.json，accent 与 app 主题/前台通知一致。
object WidgetTheme {
    val bg get() = ColorProvider(R.color.card_bg)
    val textPrimary get() = ColorProvider(R.color.card_text_primary)
    val textSecondary get() = ColorProvider(R.color.card_text_secondary)
    val accent get() = ColorProvider(R.color.card_accent)
}
