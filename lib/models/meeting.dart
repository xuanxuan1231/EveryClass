import '../util/coerce.dart';
import 'occurrence_override.dart';
import 'week_rule.dart';

/// 一条周期性排课：星期 + 时间 + 周次规则 + 例外。
///
/// 时间二选一：[customStart] 非空 → 用自定义时刻（自由，可落在节次网格外）；
/// 否则用 [startPeriod]/[endPeriod] 引用作息表节次（跟随作息）。
class Meeting {
  final String id;

  /// 星期，1–7（周一=1，对齐 `DateTime.weekday`）。
  final int weekday;

  /// 起始/结束节次（引用 `BellSchedule.periods[].index`；自定义时刻时为 0）。
  final int startPeriod;
  final int endPeriod;

  /// 自定义时刻（`HH:mm`）；非空则忽略节次/作息。
  final String? customStart;
  final String? customEnd;

  /// 可选覆盖使用的作息表；null=用 Calendar 的星期/默认作息。
  final String? bellScheduleId;

  final WeekRule weeks;

  /// 可选覆盖 `CourseEvent.defaultLocation` / `.teacher`。
  final String? location;
  final String? teacher;

  /// 调课/补课/停课/改教室，键为「原发生日期」`yyyy-MM-dd`。
  final Map<String, OccurrenceOverride> overrides;

  final Map<String, dynamic> extra;

  const Meeting({
    required this.id,
    required this.weekday,
    this.startPeriod = 0,
    this.endPeriod = 0,
    this.customStart,
    this.customEnd,
    this.bellScheduleId,
    this.weeks = WeekRule.every,
    this.location,
    this.teacher,
    this.overrides = const {},
    this.extra = const {},
  });

  bool get usesCustomTime => customStart != null && customStart!.isNotEmpty;

  Meeting copyWith({
    int? weekday,
    int? startPeriod,
    int? endPeriod,
    String? customStart,
    String? customEnd,
    String? bellScheduleId,
    WeekRule? weeks,
    String? location,
    String? teacher,
    Map<String, OccurrenceOverride>? overrides,
  }) {
    return Meeting(
      id: id,
      weekday: weekday ?? this.weekday,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
      bellScheduleId: bellScheduleId ?? this.bellScheduleId,
      weeks: weeks ?? this.weeks,
      location: location ?? this.location,
      teacher: teacher ?? this.teacher,
      overrides: overrides ?? this.overrides,
      extra: extra,
    );
  }

  factory Meeting.fromJson(Map<String, dynamic> json, {String? id}) {
    String? optStr(dynamic v) => v == null ? null : asString(v);
    final overridesRaw = asMap(pick(json, ['overrides', 'Overrides']));
    return Meeting(
      id: asString(pick(json, ['id', 'Id']) ?? id),
      weekday: asInt(pick(json, ['weekday', 'Weekday', 'WeekDay'])),
      startPeriod: asInt(pick(json, ['startPeriod', 'StartPeriod'])),
      endPeriod: asInt(pick(json, ['endPeriod', 'EndPeriod'])),
      customStart: optStr(pick(json, ['customStart', 'CustomStart'])),
      customEnd: optStr(pick(json, ['customEnd', 'CustomEnd'])),
      bellScheduleId: optStr(pick(json, ['bellScheduleId', 'BellScheduleId'])),
      weeks: WeekRule.fromJson(asMap(pick(json, ['weeks', 'Weeks']))),
      location: optStr(pick(json, ['location', 'Location'])),
      teacher: optStr(pick(json, ['teacher', 'Teacher'])),
      overrides: overridesRaw.map(
        (k, v) => MapEntry(k, OccurrenceOverride.fromJson(asMap(v))),
      ),
      extra: asMap(pick(json, ['extra', 'Extra'])),
    );
  }

  Map<String, dynamic> toJson() => {
        '@type': 'Meeting',
        'id': id,
        'weekday': weekday,
        if (!usesCustomTime) 'startPeriod': startPeriod,
        if (!usesCustomTime) 'endPeriod': endPeriod,
        if (usesCustomTime) 'customStart': customStart,
        if (usesCustomTime) 'customEnd': customEnd,
        if (bellScheduleId != null) 'bellScheduleId': bellScheduleId,
        'weeks': weeks.toJson(),
        if (location != null) 'location': location,
        if (teacher != null) 'teacher': teacher,
        if (overrides.isNotEmpty)
          'overrides': overrides.map((k, v) => MapEntry(k, v.toJson())),
        if (extra.isNotEmpty) 'extra': extra,
      };
}
