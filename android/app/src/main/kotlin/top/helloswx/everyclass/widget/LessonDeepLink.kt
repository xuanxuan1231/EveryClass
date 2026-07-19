package top.helloswx.everyclass.widget

// 桌面卡片「点课→回应用唤出详情浮窗」的深链契约：卡片侧（WidgetComposables）按此
// 构造启动 MainActivity 的显式 Intent，MainActivity 按同一批常量解析后经
// everyclass/deeplink 通道转交 Dart。两侧改动需同步。
object LessonDeepLink {
    /** 点课深链专用 action：区别于普通启动器打开（后者不带课程身份、不弹浮窗）。 */
    const val ACTION = "top.helloswx.everyclass.action.OPEN_LESSON"

    /** 课程 ID（对应 ResolvedLesson.subjectId）。 */
    const val EXTRA_SUBJECT_ID = "lesson_subject_id"

    /** 起始分钟数（距零点）：与 subjectId 一起在当天课表里定位这节课。 */
    const val EXTRA_START_MINUTE = "lesson_start_minute"

    /** data Uri scheme：仅用于让每节课的 PendingIntent 互不相同（extras 不参与
     *  PendingIntent 去重，data 参与）。 */
    const val SCHEME = "everyclass"
}
