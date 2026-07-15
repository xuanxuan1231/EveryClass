import '../models/bell_schedule.dart';
import '../models/calendar.dart';
import '../models/class_plan.dart' as ci;
import '../models/course_event.dart';
import '../models/database.dart';
import '../models/meeting.dart';
import '../models/profile.dart';
import '../models/time_layout.dart' as tl;
import '../models/week_rule.dart';

/// 把导入的 ClassIsland [Profile] 转换成新模型的一张 [Calendar]。
///
/// - 每个 `TimeLayout` → 一张 [BellSchedule]（上课点按顺序编 1-based 节次）。
/// - 每个 `Subject` → 一门 [CourseEvent]。
/// - 每个 `ClassPlan` 的第 i 个上课位 → 该科目的一条 [Meeting]（星期/周次/教室）。
class ClassIslandConverter {
  static const String _calendarId = 'imported';

  static Calendar toCalendar(
    Profile profile, {
    String calendarId = _calendarId,
    String? name,
    DateTime? firstWeekStart,
  }) {
    // 1) TimeLayouts → BellSchedules，并记住每张表里「第 i 个上课点 → 节次号」。
    final bellSchedules = <String, BellSchedule>{};
    final lessonIndexByLayout = <String, List<int>>{}; // layoutId → [节次号...]
    profile.timeLayouts.forEach((layoutId, layout) {
      final periods = <BellPeriod>[];
      final lessonIndices = <int>[];
      var classNo = 0;
      for (final item in layout.items) {
        if (item.isLesson) {
          classNo++;
          lessonIndices.add(classNo);
          periods.add(BellPeriod(
            index: classNo,
            kind: BellPeriodKind.klass,
            start: item.start,
            end: item.end,
            label: '第$classNo节',
          ));
        } else {
          periods.add(BellPeriod(
            index: 0,
            kind: item.timeType == tl.TimeType.breakTime
                ? BellPeriodKind.breakTime
                : BellPeriodKind.activity,
            start: item.start,
            end: item.end,
            label: item.breakName,
          ));
        }
      }
      bellSchedules[layoutId] =
          BellSchedule(id: layoutId, name: layout.name, periods: periods);
      lessonIndexByLayout[layoutId] = lessonIndices;
    });

    // 2) Subjects → CourseEvents（先建壳，meetings 后填）。
    final meetingsBySubject = <String, List<Meeting>>{};

    // 3) ClassPlans → Meetings。
    var meetingSeq = 0;
    profile.classPlans.forEach((planId, plan) {
      if (!plan.isEnabled || plan.isOverlay) return;
      final lessonIndices = lessonIndexByLayout[plan.timeLayoutId];
      if (lessonIndices == null) return;
      final weeks = _weekRule(plan.timeRule);
      for (var i = 0; i < plan.classes.length; i++) {
        if (i >= lessonIndices.length) break;
        final info = plan.classes[i];
        if (info.subjectId.isEmpty || !info.isEnabled) continue;
        final period = lessonIndices[i];
        meetingSeq++;
        meetingsBySubject.putIfAbsent(info.subjectId, () => []).add(Meeting(
              id: 'm$meetingSeq',
              weekday: plan.timeRule.weekDay,
              startPeriod: period,
              endPeriod: period,
              bellScheduleId: plan.timeLayoutId,
              weeks: weeks,
              location: info.room.isNotEmpty ? info.room : null,
            ));
      }
    });

    final courses = <String, CourseEvent>{};
    profile.subjects.forEach((subjectId, subject) {
      final meetings = meetingsBySubject[subjectId] ?? const <Meeting>[];
      // 无课时段的科目也保留（用户可后续排课/填教室）。
      courses[subjectId] = CourseEvent(
        id: subjectId,
        title: subject.name,
        teacher: subject.teacherName,
        defaultLocation: subject.defaultRoom,
        meetings: meetings,
      );
    });

    return Calendar(
      id: calendarId,
      name: name ?? (profile.name.isEmpty ? '导入课表' : profile.name),
      firstWeekStart: firstWeekStart,
      bellSchedules: bellSchedules,
      defaultBellScheduleId:
          bellSchedules.isNotEmpty ? bellSchedules.keys.first : '',
      courses: courses,
    );
  }

  static Database toDatabase(
    Profile profile, {
    String calendarId = _calendarId,
    DateTime? firstWeekStart,
  }) {
    final cal = toCalendar(
      profile,
      calendarId: calendarId,
      firstWeekStart: firstWeekStart,
    );
    return Database(selectedCalendarId: cal.id, calendars: {cal.id: cal});
  }

  /// ClassIsland `TimeRule` → [WeekRule]。
  /// weekCountDiv 0=每周；n=在 total 周轮换里的第 n 周（1-based → offset=n-1）。
  static WeekRule _weekRule(ci.TimeRule rule) {
    final total = rule.weekCountDivTotal <= 0 ? 2 : rule.weekCountDivTotal;
    if (rule.weekCountDiv == 0) return WeekRule.every;
    return WeekRule(interval: total, offsets: [rule.weekCountDiv - 1]);
  }
}
