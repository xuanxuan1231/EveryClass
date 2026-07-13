import '../util/coerce.dart';

/// 单次课的例外（调课 / 补课 / 停课 / 改教室），对齐 JSCalendar
/// `recurrenceOverrides` 的 PatchObject 语义。存于 [Meeting.overrides]，键为
/// 该次课「原本发生的日期」`yyyy-MM-dd`（补课 [added] 时键为补课当天）。
class OccurrenceOverride {
  /// 停课：这一天不再有这节课。
  final bool excluded;

  /// 补课：规则外新增的一次（键日期即为补课当天）。
  final bool added;

  /// 调课改到别的日期（`yyyy-MM-dd`）；null 表示不改日期。
  final String? movedToDate;

  /// 覆盖节次（null 表示沿用 Meeting）。
  final int? startPeriod;
  final int? endPeriod;

  /// 覆盖自定义时刻（`HH:mm`；null 表示沿用 Meeting）。
  final String? customStart;
  final String? customEnd;

  /// 覆盖教室 / 教师（null 表示沿用）。
  final String? location;
  final String? teacher;

  const OccurrenceOverride({
    this.excluded = false,
    this.added = false,
    this.movedToDate,
    this.startPeriod,
    this.endPeriod,
    this.customStart,
    this.customEnd,
    this.location,
    this.teacher,
  });

  factory OccurrenceOverride.fromJson(Map<String, dynamic> json) {
    int? optInt(dynamic v) => v == null ? null : asInt(v);
    String? optStr(dynamic v) => v == null ? null : asString(v);
    return OccurrenceOverride(
      excluded: asBool(pick(json, ['excluded', 'Excluded'])),
      added: asBool(pick(json, ['added', 'Added'])),
      movedToDate: optStr(pick(json, ['movedToDate', 'MovedToDate'])),
      startPeriod: optInt(pick(json, ['startPeriod', 'StartPeriod'])),
      endPeriod: optInt(pick(json, ['endPeriod', 'EndPeriod'])),
      customStart: optStr(pick(json, ['customStart', 'CustomStart'])),
      customEnd: optStr(pick(json, ['customEnd', 'CustomEnd'])),
      location: optStr(pick(json, ['location', 'Location'])),
      teacher: optStr(pick(json, ['teacher', 'Teacher'])),
    );
  }

  Map<String, dynamic> toJson() => {
        if (excluded) 'excluded': true,
        if (added) 'added': true,
        if (movedToDate != null) 'movedToDate': movedToDate,
        if (startPeriod != null) 'startPeriod': startPeriod,
        if (endPeriod != null) 'endPeriod': endPeriod,
        if (customStart != null) 'customStart': customStart,
        if (customEnd != null) 'customEnd': customEnd,
        if (location != null) 'location': location,
        if (teacher != null) 'teacher': teacher,
      };
}
