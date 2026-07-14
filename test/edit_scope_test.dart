import 'package:everyclass/app_state.dart';
import 'package:everyclass/models/calendar.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/meeting.dart';
import 'package:everyclass/models/occurrence_override.dart';
import 'package:everyclass/models/week_rule.dart';
import 'package:everyclass/services/schedule_service.dart';
import 'package:everyclass/util/edit_scope.dart';
import 'package:flutter_test/flutter_test.dart';

const _bell = AppState.defaultBellSchedule;

void main() {
  // 学期第 1 周周一 = 2026-03-02（周一）。周二课：第 1 周 = 03-03，
  // 第 2 周 = 03-10，第 3 周 = 03-17。
  final firstWeekStart = DateTime(2026, 3, 2);

  const course = CourseEvent(id: 'c1', title: '语文', teacher: '张老师');

  Meeting meeting({Map<String, OccurrenceOverride> overrides = const {}}) =>
      Meeting(
        id: 'm1',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        weeks: const WeekRule(fromWeek: 1, toWeek: 4),
        teacher: '张老师',
        overrides: overrides,
      );

  Calendar calWith(Meeting m) => Calendar(
        id: 'cal',
        firstWeekStart: firstWeekStart,
        bellSchedules: {'bs': _bell},
        defaultBellScheduleId: 'bs',
        courses: {
          'c1': CourseEvent(id: 'c1', title: '语文', meetings: [m]),
        },
      );

  /// 从某时段某天的生效值出发、改若干字段后的 [OccurrenceEdit]。
  OccurrenceEdit editFrom(
    Meeting m,
    DateTime day, {
    DateTime? date,
    String? teacher,
    String? location,
    String? description,
    int? startPeriod,
    int? endPeriod,
  }) {
    final base = effectiveOccurrenceEdit(course: course, meeting: m, day: day);
    return OccurrenceEdit(
      date: date ?? base.date,
      usesCustomTime: base.usesCustomTime,
      startPeriod: startPeriod ?? base.startPeriod,
      endPeriod: endPeriod ?? base.endPeriod,
      customStart: base.customStart,
      customEnd: base.customEnd,
      teacher: teacher ?? base.teacher,
      location: location ?? base.location,
      description: description ?? base.description,
    );
  }

  group('effectiveOccurrenceEdit（表单基线）', () {
    test('无 override 回落时段/课程值', () {
      final e = effectiveOccurrenceEdit(
          course: course, meeting: meeting(), day: DateTime(2026, 3, 10));
      expect(e.teacher, '张老师');
      expect(e.startPeriod, 1);
      expect(e.endPeriod, 2);
      expect(e.usesCustomTime, isFalse);
    });

    test('有 override 时取生效值，含 movedToDate 的调后日期', () {
      final m = meeting(overrides: const {
        '2026-03-10':
            OccurrenceOverride(movedToDate: '2026-03-12', teacher: '王老师'),
      });
      final e = effectiveOccurrenceEdit(
          course: course, meeting: m, day: DateTime(2026, 3, 10));
      expect(e.date, DateTime(2026, 3, 12));
      expect(e.teacher, '王老师');
    });
  });

  group('applyOccurrenceEditThisOnly（仅修改本次）', () {
    test('只写改动字段；其他日期不受影响', () {
      final m = meeting();
      final result = applyOccurrenceEditThisOnly(
        course: course,
        meeting: m,
        day: DateTime(2026, 3, 10),
        edit: editFrom(m, DateTime(2026, 3, 10), teacher: '王老师'),
      );
      expect(result.teacher, '张老师'); // 基础不变
      final ov = result.overrides['2026-03-10']!;
      expect(ov.teacher, '王老师');
      expect(ov.location, isNull);
      expect(ov.startPeriod, isNull);

      final svc = ScheduleService(calWith(result));
      expect(
        svc.scheduleFor(DateTime(2026, 3, 10)).lessons.single.teacher,
        '王老师',
      );
      expect(
        svc.scheduleFor(DateTime(2026, 3, 3)).lessons.single.teacher,
        '张老师',
      );
    });

    test('保留该日期已有补丁的其他字段', () {
      final m = meeting(
        overrides: const {'2026-03-10': OccurrenceOverride(location: 'B2')},
      );
      final result = applyOccurrenceEditThisOnly(
        course: course,
        meeting: m,
        day: DateTime(2026, 3, 10),
        edit: editFrom(m, DateTime(2026, 3, 10), startPeriod: 3, endPeriod: 4),
      );
      final ov = result.overrides['2026-03-10']!;
      expect(ov.location, 'B2');
      expect(ov.startPeriod, 3);
      expect(ov.endPeriod, 4);
    });

    test('改回继承值撤销覆盖；补丁全空则删键', () {
      final m = meeting(
        overrides: const {'2026-03-10': OccurrenceOverride(teacher: '王老师')},
      );
      // 生效教师=王老师，改回张老师（= meeting.teacher）→ 撤销覆盖。
      final result = applyOccurrenceEditThisOnly(
        course: course,
        meeting: m,
        day: DateTime(2026, 3, 10),
        edit: editFrom(m, DateTime(2026, 3, 10), teacher: '张老师'),
      );
      expect(result.overrides.containsKey('2026-03-10'), isFalse);
    });

    test('本次备注写入 override', () {
      final m = meeting();
      final result = applyOccurrenceEditThisOnly(
        course: course,
        meeting: m,
        day: DateTime(2026, 3, 10),
        edit: editFrom(m, DateTime(2026, 3, 10), description: '今天测验'),
      );
      expect(result.overrides['2026-03-10']!.description, '今天测验');
    });

    test('改日期 → movedToDate', () {
      final m = meeting();
      final result = applyOccurrenceEditThisOnly(
        course: course,
        meeting: m,
        day: DateTime(2026, 3, 10),
        edit: editFrom(m, DateTime(2026, 3, 10), date: DateTime(2026, 3, 12)),
      );
      expect(result.weekday, 2); // 基础不变
      expect(result.overrides['2026-03-10']!.movedToDate, '2026-03-12');

      final svc = ScheduleService(calWith(result));
      expect(svc.scheduleFor(DateTime(2026, 3, 10)).lessons, isEmpty);
      expect(svc.scheduleFor(DateTime(2026, 3, 12)).lessons, hasLength(1));
      expect(svc.scheduleFor(DateTime(2026, 3, 3)).lessons, hasLength(1));
    });

    test('补课改日期 → 重建键（调度引擎按键日期生成）', () {
      final m = meeting(
        overrides: const {
          '2026-03-11': OccurrenceOverride(added: true, teacher: '王老师'),
        },
      );
      final result = applyOccurrenceEditThisOnly(
        course: course,
        meeting: m,
        day: DateTime(2026, 3, 11),
        edit: editFrom(m, DateTime(2026, 3, 11), date: DateTime(2026, 3, 13)),
      );
      expect(result.overrides.containsKey('2026-03-11'), isFalse);
      final ov = result.overrides['2026-03-13']!;
      expect(ov.added, isTrue);
      expect(ov.teacher, '王老师');
      expect(ov.movedToDate, isNull);

      final svc = ScheduleService(calWith(result));
      expect(svc.scheduleFor(DateTime(2026, 3, 13)).lessons, hasLength(1));
    });
  });

  group('applyOccurrenceEditFromWeek（修改本次及以后）', () {
    test('编辑日的同字段旧补丁被剥离，其他日期补丁不触碰', () {
      // 编辑日（第 2 周 03-10）已有教师+地点补丁；B 日（第 3 周 03-17）另有
      // 教师补丁。把教师改成王老师、本次及以后：编辑日的教师补丁被新基础值
      // 取代（地点补丁保留），B 日自己的单次调整原样保留。
      final m = meeting(overrides: const {
        '2026-03-10': OccurrenceOverride(teacher: '代课刘老师', location: 'B2'),
        '2026-03-17': OccurrenceOverride(teacher: '另一位老师'),
      });
      final parts = applyOccurrenceEditFromWeek(
        course: course,
        meeting: m,
        day: DateTime(2026, 3, 10),
        week: 2,
        newId: 'm2',
        edit: editFrom(m, DateTime(2026, 3, 10), teacher: '王老师'),
      );
      expect(parts, hasLength(2));
      final future = parts.firstWhere((p) => p.id == 'm2');
      expect(future.teacher, '王老师');
      final d10 = future.overrides['2026-03-10']!;
      expect(d10.teacher, isNull); // 被新基础值取代
      expect(d10.location, 'B2'); // 与本次编辑无关，保留
      expect(future.overrides['2026-03-17']!.teacher, '另一位老师');

      final cal = Calendar(
        id: 'cal',
        firstWeekStart: firstWeekStart,
        bellSchedules: {'bs': _bell},
        defaultBellScheduleId: 'bs',
        courses: {'c1': CourseEvent(id: 'c1', title: '语文', meetings: parts)},
      );
      final svc = ScheduleService(cal);
      expect(svc.scheduleFor(DateTime(2026, 3, 3)).lessons.single.teacher,
          '张老师'); // 旧段
      final d10Lesson = svc.scheduleFor(DateTime(2026, 3, 10)).lessons.single;
      expect(d10Lesson.teacher, '王老师');
      expect(d10Lesson.room, 'B2');
      expect(svc.scheduleFor(DateTime(2026, 3, 17)).lessons.single.teacher,
          '另一位老师');
    });

    test('未被升级的字段（本次备注）作为残留补丁留在本次', () {
      final m = meeting();
      final parts = applyOccurrenceEditFromWeek(
        course: course,
        meeting: m,
        day: DateTime(2026, 3, 10),
        week: 2,
        newId: 'm2',
        edit: editFrom(m, DateTime(2026, 3, 10),
            teacher: '王老师', description: '仅这次的备注'),
      );
      final future = parts.firstWhere((p) => p.id == 'm2');
      expect(future.teacher, '王老师'); // 升级为基础值
      // 备注只能按次，留作 A 日（本周二 03-10）的残留补丁。
      expect(future.overrides['2026-03-10']!.description, '仅这次的备注');
    });
  });

  group('cancelOccurrence（本次停课）', () {
    test('常规课写 excluded 并保留其他字段', () {
      final m = meeting(
        overrides: const {'2026-03-10': OccurrenceOverride(location: 'B2')},
      );
      final result = cancelOccurrence(m, DateTime(2026, 3, 10));
      final ov = result.overrides['2026-03-10']!;
      expect(ov.excluded, isTrue);
      expect(ov.location, 'B2');

      final svc = ScheduleService(calWith(result));
      expect(svc.scheduleFor(DateTime(2026, 3, 10)).lessons, isEmpty);
      expect(svc.scheduleFor(DateTime(2026, 3, 3)).lessons, hasLength(1));
    });

    test('补课停课 = 直接移除该条', () {
      final m = meeting(
        overrides: const {'2026-03-11': OccurrenceOverride(added: true)},
      );
      final result = cancelOccurrence(m, DateTime(2026, 3, 11));
      expect(result.overrides.containsKey('2026-03-11'), isFalse);
    });
  });

  group('splitMeetingFromWeek（底层拆分）', () {
    test('用户例：B 日自己的补丁字段不变，未覆盖字段跟随新基础值', () {
      final original = meeting(
        overrides: const {'2026-03-17': OccurrenceOverride(teacher: '代课刘老师')},
      );
      final edited = original.copyWith(location: 'C3');
      final parts = splitMeetingFromWeek(
        original: original,
        edited: edited,
        day: DateTime(2026, 3, 10),
        week: 2,
        newId: 'm2',
      );

      expect(parts, hasLength(2));
      final past = parts[0];
      final future = parts[1];
      expect(past.id, 'm1');
      expect(past.location, isNull);
      expect(past.weeks.matches(1), isTrue);
      expect(past.weeks.matches(2), isFalse);
      expect(future.id, 'm2');
      expect(future.location, 'C3');
      expect(future.weeks.matches(2), isTrue);
      expect(future.weeks.matches(4), isTrue);
      expect(future.overrides.keys, ['2026-03-17']);
      expect(past.overrides, isEmpty);
    });

    test('从第 1 周拆分：旧段消失，只剩新段', () {
      final original = meeting();
      final edited = original.copyWith(startPeriod: 3, endPeriod: 4);
      final parts = splitMeetingFromWeek(
        original: original,
        edited: edited,
        day: DateTime(2026, 3, 3),
        week: 1,
        newId: 'm2',
      );
      expect(parts, hasLength(1));
      expect(parts.single.id, 'm2');
      expect(parts.single.startPeriod, 3);
    });

    test('旧段只剩早于拆分日的单次调整时，不再有常规重复', () {
      final original = Meeting(
        id: 'm1',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 1,
        weeks: const WeekRule(fromWeek: 2, toWeek: 4),
        overrides: const {'2026-03-03': OccurrenceOverride(added: true)},
      );
      final edited = original.copyWith(startPeriod: 2, endPeriod: 2);
      final parts = splitMeetingFromWeek(
        original: original,
        edited: edited,
        day: DateTime(2026, 3, 10),
        week: 2,
        newId: 'm2',
      );
      expect(parts, hasLength(2));
      final past = parts[0];
      expect(past.overrides.keys, ['2026-03-03']);
      for (var w = 1; w <= 8; w++) {
        expect(past.weeks.matches(w), isFalse, reason: 'week $w');
      }
    });

    test('无上界规则（每周）拆分后仍无上界，不被默认 20 周截断', () {
      final original = meeting().copyWith(weeks: WeekRule.every);
      final edited = original.copyWith(location: 'C3');
      // 第 22 周（超出默认 20 周网格）拆分。
      final parts = splitMeetingFromWeek(
        original: original,
        edited: edited,
        day: DateTime(2026, 7, 28),
        week: 22,
        newId: 'm2',
      );

      expect(parts, hasLength(2));
      final past = parts[0];
      final future = parts[1];
      // 旧段：1-21 周，包含默认网格之外的第 21 周。
      expect(past.weeks.matches(21), isTrue);
      expect(past.weeks.matches(22), isFalse);
      // 新段：22 周起、无上界（远超 20 周仍生效）。
      expect(future.weeks.toWeek, 0);
      expect(future.weeks.matches(21), isFalse);
      expect(future.weeks.matches(22), isTrue);
      expect(future.weeks.matches(50), isTrue);
      expect(future.location, 'C3');
    });

    test('无上界单周规则拆分：奇偶相位保持、上界保持无限', () {
      final original = meeting()
          .copyWith(weeks: const WeekRule(interval: 2, offset: 0)); // 单周
      final edited = original.copyWith(startPeriod: 3, endPeriod: 3);
      final parts = splitMeetingFromWeek(
        original: original,
        edited: edited,
        day: DateTime(2026, 7, 21),
        week: 21,
        newId: 'm2',
      );

      expect(parts, hasLength(2));
      final past = parts[0];
      final future = parts[1];
      // 旧段：1-20 的单周。
      expect(past.weeks.matches(19), isTrue);
      expect(past.weeks.matches(20), isFalse); // 双周
      expect(past.weeks.matches(21), isFalse); // 已归新段
      // 新段：21 周起的单周，相位不变、无上界。
      expect(future.weeks.toWeek, 0);
      expect(future.weeks.matches(21), isTrue);
      expect(future.weeks.matches(22), isFalse); // 双周
      expect(future.weeks.matches(43), isTrue);
    });
  });
}
