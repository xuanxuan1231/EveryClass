import '../util/coerce.dart';
import 'bell_schedule.dart';
import 'course_event.dart';

/// 一张学期课表：自包含（作息表、课程、例外都在内）。多课表=多个 [Calendar]。
///
/// 用户无需填学期起止，只需 [firstWeekStart]（第一周的周一，用于把周次/轮换换算
/// 成绝对日期）。
class Calendar {
  final String id;
  final String name;
  final String timeZone;

  /// 第一周所在的日期（通常取周一）；null 表示不做周次/轮换过滤。
  final DateTime? firstWeekStart;

  /// 学期总周数（可选，缺省从课程周次范围推导）。
  final int totalWeeks;

  final String color;

  final Map<String, BellSchedule> bellSchedules;

  /// 按星期指派作息（1–7 → bellScheduleId）；缺则用 [defaultBellScheduleId]。
  final Map<int, String> weekdayBellSchedule;
  final String defaultBellScheduleId;

  final Map<String, CourseEvent> courses;

  final Map<String, dynamic> extra;

  const Calendar({
    required this.id,
    this.name = '',
    this.timeZone = 'Asia/Shanghai',
    this.firstWeekStart,
    this.totalWeeks = 0,
    this.color = '',
    this.bellSchedules = const {},
    this.weekdayBellSchedule = const {},
    this.defaultBellScheduleId = '',
    this.courses = const {},
    this.extra = const {},
  });

  Calendar copyWith({
    String? name,
    DateTime? firstWeekStart,
    bool clearFirstWeekStart = false,
    int? totalWeeks,
    Map<String, BellSchedule>? bellSchedules,
    Map<int, String>? weekdayBellSchedule,
    String? defaultBellScheduleId,
    Map<String, CourseEvent>? courses,
  }) {
    return Calendar(
      id: id,
      name: name ?? this.name,
      timeZone: timeZone,
      firstWeekStart:
          clearFirstWeekStart ? null : (firstWeekStart ?? this.firstWeekStart),
      totalWeeks: totalWeeks ?? this.totalWeeks,
      color: color,
      bellSchedules: bellSchedules ?? this.bellSchedules,
      weekdayBellSchedule: weekdayBellSchedule ?? this.weekdayBellSchedule,
      defaultBellScheduleId:
          defaultBellScheduleId ?? this.defaultBellScheduleId,
      courses: courses ?? this.courses,
      extra: extra,
    );
  }

  /// 某星期该用哪张作息表：显式指派 → 默认 → 唯一一张（便利回退）。
  BellSchedule? bellScheduleForWeekday(int weekday) {
    final byDay = weekdayBellSchedule[weekday];
    if (byDay != null && bellSchedules[byDay] != null) {
      return bellSchedules[byDay];
    }
    final def = bellSchedules[defaultBellScheduleId];
    if (def != null) return def;
    if (bellSchedules.length == 1) return bellSchedules.values.first;
    return null;
  }

  factory Calendar.fromJson(Map<String, dynamic> json, {String? id}) {
    final fws = asString(pick(json, ['firstWeekStart', 'FirstWeekStart']));
    return Calendar(
      id: asString(pick(json, ['id', 'Id']) ?? id),
      name: asString(pick(json, ['name', 'Name'])),
      timeZone: asString(
        pick(json, ['timeZone', 'TimeZone']),
        fallback: 'Asia/Shanghai',
      ),
      firstWeekStart: fws.isEmpty ? null : DateTime.tryParse(fws),
      totalWeeks: asInt(pick(json, ['totalWeeks', 'TotalWeeks'])),
      color: asString(pick(json, ['color', 'Color'])),
      bellSchedules: asMap(pick(json, ['bellSchedules', 'BellSchedules'])).map(
        (k, v) => MapEntry(k, BellSchedule.fromJson(asMap(v), id: k)),
      ),
      weekdayBellSchedule:
          asMap(pick(json, ['weekdayBellSchedule', 'WeekdayBellSchedule'])).map(
        (k, v) => MapEntry(int.tryParse(k) ?? 0, asString(v)),
      ),
      defaultBellScheduleId: asString(
        pick(json, ['defaultBellScheduleId', 'DefaultBellScheduleId']),
      ),
      courses: asMap(pick(json, ['courses', 'Courses'])).map(
        (k, v) => MapEntry(k, CourseEvent.fromJson(asMap(v), id: k)),
      ),
      extra: asMap(pick(json, ['extra', 'Extra'])),
    );
  }

  Map<String, dynamic> toJson() => {
        '@type': 'Calendar',
        'id': id,
        'name': name,
        'timeZone': timeZone,
        if (firstWeekStart != null)
          'firstWeekStart': _ymd(firstWeekStart!),
        if (totalWeeks > 0) 'totalWeeks': totalWeeks,
        if (color.isNotEmpty) 'color': color,
        'bellSchedules':
            bellSchedules.map((k, v) => MapEntry(k, v.toJson())),
        if (weekdayBellSchedule.isNotEmpty)
          'weekdayBellSchedule': weekdayBellSchedule.map(
            (k, v) => MapEntry(k.toString(), v),
          ),
        if (defaultBellScheduleId.isNotEmpty)
          'defaultBellScheduleId': defaultBellScheduleId,
        'courses': courses.map((k, v) => MapEntry(k, v.toJson())),
        if (extra.isNotEmpty) 'extra': extra,
      };

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
