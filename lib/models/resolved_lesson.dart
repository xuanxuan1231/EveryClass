import 'subject.dart';

/// 调度引擎的计算产物：某一天的一节具体课程。
///
/// 已把 `ClassInfo` + `Subject` + `TimeLayoutItem` 解析合并，UI 与通知层直接消费，
/// 不必再回查档案。
class ResolvedLesson {
  final String subjectId;
  final Subject subject;

  /// 已解析的教室：优先 `ClassInfo.room`，回退 `Subject.defaultRoom`。
  final String room;

  /// 距零点的开始/结束时刻。
  final Duration start;
  final Duration end;

  /// 第几节（在当天上课时间点中的 1-based 序号）。
  final int period;

  const ResolvedLesson({
    required this.subjectId,
    required this.subject,
    required this.room,
    required this.start,
    required this.end,
    required this.period,
  });

  String get subjectName => subject.name;
  String get teacher => subject.teacherName;

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
