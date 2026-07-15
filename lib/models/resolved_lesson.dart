/// 调度引擎的计算产物：某一天的一节具体课程。
///
/// 已把 `CourseEvent` + `Meeting` + 作息/自定义时刻解析合并，UI 与通知层直接消费，
/// 不必再回查课表。
class ResolvedLesson {
  /// 所属课程 ID（原 `subjectId`，保留名字以兼容通知层）。
  final String subjectId;

  final String subjectName;
  final String teacher;

  /// 已解析的教室（例外 > Meeting > 课程默认）。
  final String room;

  /// 距零点的开始/结束时刻。
  final Duration start;
  final Duration end;

  /// 第几节（当天已解析课程中的 1-based 顺序序号）。
  final int period;

  /// 起止节次（引用作息表；自定义时刻时为 0）。
  final int startPeriod;
  final int endPeriod;

  /// 课程颜色（`#RRGGBB`，可空）。
  final String color;

  /// 已解析的本次备注（例外 > 课程默认；可空）。
  final String description;

  /// 来源 `Meeting.id`（可空，兼容旧调用），供「编辑本次/本次及以后」定位时段。
  final String meetingId;

  /// 这次课的「原发生日期」`yyyy-MM-dd`（即 `Meeting.overrides` 的键；未被
  /// 调课时就是展示当天）。可空，兼容旧调用。
  final String originDate;

  const ResolvedLesson({
    required this.subjectId,
    required this.subjectName,
    required this.teacher,
    required this.room,
    required this.start,
    required this.end,
    required this.period,
    this.startPeriod = 0,
    this.endPeriod = 0,
    this.color = '',
    this.description = '',
    this.meetingId = '',
    this.originDate = '',
  });

  /// 结合具体日期得到开始/结束的绝对时间。
  DateTime startOn(DateTime day) =>
      DateTime(day.year, day.month, day.day).add(start);
  DateTime endOn(DateTime day) =>
      DateTime(day.year, day.month, day.day).add(end);

  bool isCurrentAt(DateTime now) {
    final s = startOn(now);
    final e = endOn(now);
    return !now.isBefore(s) && now.isBefore(e);
  }
}
