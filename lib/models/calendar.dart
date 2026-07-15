import '../util/coerce.dart';
import 'bell_schedule.dart';
import 'course_event.dart';

/// 一张学期课表：自包含（作息表、课程、例外都在内）。多课表=多个 [Calendar]。
///
/// 用户只需设置学期开始日期 [firstWeekStart]（第一周的周一，用于把周次/轮换
/// 换算成绝对日期）。学期没有结束日期——周次是无限的，[weekCount] 只是按课程
/// 排课数据推导出来的展示值。
class Calendar {
  /// 没有任何排课约束周次时，[weekCount] 的兜底周数（与周次勾选网格一致）。
  static const int defaultWeekCount = 20;

  final String id;
  final String name;
  final String timeZone;

  /// 第一周所在的日期（通常取周一），用于推断周次以排课；null 表示用户尚未
  /// 设置，此时不做周次/轮换过滤。
  final DateTime? firstWeekStart;

  final String color;

  /// 备注（用户自由填写，如「大二下学期」）。
  final String note;

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
    this.color = '',
    this.note = '',
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
    String? color,
    String? note,
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
      color: color ?? this.color,
      note: note ?? this.note,
      bellSchedules: bellSchedules ?? this.bellSchedules,
      weekdayBellSchedule: weekdayBellSchedule ?? this.weekdayBellSchedule,
      defaultBellScheduleId:
          defaultBellScheduleId ?? this.defaultBellScheduleId,
      courses: courses ?? this.courses,
      extra: extra,
    );
  }

  /// 全部作息表中最大的上课节次序号（无作息或无上课格时为 0）。
  int get maxClassPeriod {
    var max = 0;
    for (final bell in bellSchedules.values) {
      for (final p in bell.periods) {
        if (p.isClass && p.index > max) max = p.index;
      }
    }
    return max;
  }

  /// 学期周数（自动推导，不可手动设置）：取全部排课周次规则引用的最大周
  /// （范围上界与显式周列表）；没有任何有界规则时兜底 [defaultWeekCount]。
  int get weekCount {
    var max = 0;
    for (final course in courses.values) {
      for (final meeting in course.meetings) {
        final rule = meeting.weeks;
        if (rule.toWeek > max) max = rule.toWeek;
        for (final w in rule.include) {
          if (w > max) max = w;
        }
      }
    }
    return max > 0 ? max : defaultWeekCount;
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
      color: asString(pick(json, ['color', 'Color'])),
      note: asString(pick(json, ['note', 'Note'])),
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
        if (color.isNotEmpty) 'color': color,
        if (note.isNotEmpty) 'note': note,
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
