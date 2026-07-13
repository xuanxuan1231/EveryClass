import 'package:everyclass/data/classisland_importer.dart';
import 'package:everyclass/models/bell_schedule.dart';
import 'package:everyclass/models/calendar.dart';
import 'package:everyclass/models/course_event.dart';
import 'package:everyclass/models/meeting.dart';
import 'package:everyclass/models/occurrence_override.dart';
import 'package:everyclass/models/week_rule.dart';
import 'package:everyclass/services/schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 合成的"有课"档案（ClassIsland 格式，经导入器转换）：周一两节（语文、数学）。
const _populated = '''
{
  "Name": "test",
  "Subjects": {
    "s-yuwen": {"Name":"语文","Initial":"语","TeacherName":"张老师","IsOutDoor":false},
    "s-shuxue": {"Name":"数学","Initial":"数","TeacherName":"李老师","IsOutDoor":false,"AttachedObjects":{"everyclass.room":"A101"}}
  },
  "TimeLayouts": {
    "t1": {"Name":"标准","Layouts":[
      {"StartTime":"08:00:00","EndTime":"08:45:00","TimeType":0},
      {"StartTime":"08:45:00","EndTime":"08:55:00","TimeType":1},
      {"StartTime":"08:55:00","EndTime":"09:40:00","TimeType":0}
    ]}
  },
  "ClassPlans": {
    "p-mon": {"Name":"周一","TimeLayoutId":"t1","TimeRule":{"WeekDay":1,"WeekCountDiv":0,"WeekCountDivTotal":2},"Classes":[
      {"SubjectId":"s-yuwen"},
      {"SubjectId":"s-shuxue","AttachedObjects":{"everyclass.room":"B203"}}
    ],"IsEnabled":true}
  }
}
''';

/// 单双周档案：同为周二，单周语文、双周数学。
const _alternating = '''
{
  "Subjects": {"a":{"Name":"语文"},"b":{"Name":"数学"}},
  "TimeLayouts": {"t":{"Name":"t","Layouts":[{"StartTime":"08:00:00","EndTime":"08:45:00","TimeType":0}]}},
  "ClassPlans": {
    "odd":{"Name":"单周","TimeLayoutId":"t","TimeRule":{"WeekDay":2,"WeekCountDiv":1,"WeekCountDivTotal":2},"Classes":[{"SubjectId":"a"}],"IsEnabled":true},
    "even":{"Name":"双周","TimeLayoutId":"t","TimeRule":{"WeekDay":2,"WeekCountDiv":2,"WeekCountDivTotal":2},"Classes":[{"SubjectId":"b"}],"IsEnabled":true}
  }
}
''';

/// 手工构造的原生 Calendar：作息表 + 一门课，供例外/自定义时刻用例复用。
Calendar _nativeCalendar({
  Map<String, OccurrenceOverride> overrides = const {},
  Meeting? extraMeeting,
  DateTime? firstWeekStart,
  WeekRule weeks = WeekRule.every,
}) {
  final bell = BellSchedule(
    id: 'bs',
    name: '标准',
    periods: const [
      BellPeriod(
          index: 1,
          kind: BellPeriodKind.klass,
          start: Duration(hours: 8),
          end: Duration(hours: 8, minutes: 45)),
      BellPeriod(
          index: 0,
          kind: BellPeriodKind.breakTime,
          start: Duration(hours: 8, minutes: 45),
          end: Duration(hours: 8, minutes: 55)),
      BellPeriod(
          index: 2,
          kind: BellPeriodKind.klass,
          start: Duration(hours: 8, minutes: 55),
          end: Duration(hours: 9, minutes: 40)),
    ],
  );
  final meetings = <Meeting>[
    Meeting(
      id: 'm1',
      weekday: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: weeks,
      overrides: overrides,
    ),
    ?extraMeeting,
  ];
  return Calendar(
    id: 'cal',
    name: '测试学期',
    firstWeekStart: firstWeekStart ?? DateTime(2026, 7, 6),
    bellSchedules: {'bs': bell},
    defaultBellScheduleId: 'bs',
    courses: {
      'c1': CourseEvent(
        id: 'c1',
        title: '高数',
        teacher: '李老师',
        defaultLocation: '教三-201',
        color: '#F03E3E',
        meetings: meetings,
      ),
    },
  );
}

void main() {
  final monday = DateTime(2026, 7, 6); // 2026-07-06 是周一

  test('前置断言：2026-07-06 是周一', () {
    expect(monday.weekday, DateTime.monday);
  });

  group('scheduleFor（ClassIsland 导入路径）', () {
    final svc = ScheduleService(ClassIslandImporter.parse(_populated).selected!);

    test('周一两节课，节次连续', () {
      final s = svc.scheduleFor(monday);
      expect(s.lessons.length, 2);
      expect(s.lessons[0].subjectName, '语文');
      expect(s.lessons[0].period, 1);
      expect(s.lessons[0].start, const Duration(hours: 8));
      expect(s.lessons[1].subjectName, '数学');
      expect(s.lessons[1].period, 2);
      expect(s.lessons[1].start, const Duration(hours: 8, minutes: 55));
    });

    test('教室解析：Meeting.location 覆盖课程默认教室', () {
      final s = svc.scheduleFor(monday);
      expect(s.lessons[0].room, ''); // 语文无教室
      expect(s.lessons[1].room, 'B203'); // 数学 B203 覆盖科目默认 A101
    });

    test('非上课日无课', () {
      expect(svc.scheduleFor(monday.add(const Duration(days: 1))).isEmpty, true);
    });
  });

  group('current/next', () {
    final svc = ScheduleService(ClassIslandImporter.parse(_populated).selected!);

    test('currentLesson', () {
      expect(svc.currentLesson(DateTime(2026, 7, 6, 8, 30))?.subjectName, '语文');
      expect(svc.currentLesson(DateTime(2026, 7, 6, 8, 50)), isNull); // 课间
      expect(svc.currentLesson(DateTime(2026, 7, 6, 9, 0))?.subjectName, '数学');
    });

    test('nextLesson', () {
      expect(svc.nextLesson(DateTime(2026, 7, 6, 7, 0))?.subjectName, '语文');
      expect(svc.nextLesson(DateTime(2026, 7, 6, 8, 30))?.subjectName, '数学');
      expect(svc.nextLesson(DateTime(2026, 7, 6, 9, 0)), isNull);
    });
  });

  group('单双周轮换', () {
    final tuesdayW1 = DateTime(2026, 7, 7); // 第 1 周周二
    final tuesdayW2 = DateTime(2026, 7, 14); // 第 2 周周二

    test('前置断言：两天都是周二', () {
      expect(tuesdayW1.weekday, DateTime.tuesday);
      expect(tuesdayW2.weekday, DateTime.tuesday);
    });

    test('第一周=7/6 那周 → 单周选语文、双周选数学', () {
      final db = ClassIslandImporter.parse(_alternating, firstWeekStart: monday);
      final svc = ScheduleService(db.selected!);
      expect(svc.scheduleFor(tuesdayW1).lessons.single.subjectName, '语文');
      expect(svc.scheduleFor(tuesdayW2).lessons.single.subjectName, '数学');
    });

    test('未设第一周 → 不过滤轮换（两门课都出现）也不崩溃', () {
      final svc = ScheduleService(ClassIslandImporter.parse(_alternating).selected!);
      expect(svc.scheduleFor(tuesdayW1).lessons.length, 2);
    });
  });

  group('原生模型：跨节次 + 自定义时刻', () {
    test('引用节次 1-2 → 起止跨两节', () {
      final svc = ScheduleService(_nativeCalendar());
      final s = svc.scheduleFor(monday);
      expect(s.lessons.single.start, const Duration(hours: 8));
      expect(s.lessons.single.end, const Duration(hours: 9, minutes: 40));
      expect(s.lessons.single.room, '教三-201');
      expect(s.lessons.single.color, '#F03E3E');
    });

    test('自定义时刻不依赖作息（晚自习 19:30–21:00）', () {
      final svc = ScheduleService(_nativeCalendar(
        extraMeeting: const Meeting(
          id: 'm-night',
          weekday: 1,
          customStart: '19:30',
          customEnd: '21:00',
        ),
      ));
      final s = svc.scheduleFor(monday);
      expect(s.lessons.length, 2);
      expect(s.lessons.last.start, const Duration(hours: 19, minutes: 30));
      expect(s.lessons.last.end, const Duration(hours: 21));
      expect(s.lessons.last.startPeriod, 0); // 自定义时刻不占节次
    });
  });

  group('例外：停课 / 调课 / 补课 / 改教室', () {
    test('excluded 停课当天无课', () {
      final svc = ScheduleService(_nativeCalendar(
        overrides: const {'2026-07-06': OccurrenceOverride(excluded: true)},
      ));
      expect(svc.scheduleFor(monday).isEmpty, true);
      // 下周一不受影响
      expect(
        svc.scheduleFor(monday.add(const Duration(days: 7))).lessons.length,
        1,
      );
    });

    test('改教室只影响当天', () {
      final svc = ScheduleService(_nativeCalendar(
        overrides: const {
          '2026-07-06': OccurrenceOverride(location: '实验楼-305'),
        },
      ));
      expect(svc.scheduleFor(monday).lessons.single.room, '实验楼-305');
      expect(
        svc
            .scheduleFor(monday.add(const Duration(days: 7)))
            .lessons
            .single
            .room,
        '教三-201',
      );
    });

    test('movedToDate 调课：原日消失、目标日出现', () {
      final saturday = DateTime(2026, 7, 11);
      final svc = ScheduleService(_nativeCalendar(
        overrides: const {
          '2026-07-06': OccurrenceOverride(movedToDate: '2026-07-11'),
        },
      ));
      expect(svc.scheduleFor(monday).isEmpty, true);
      expect(svc.scheduleFor(saturday).lessons.single.subjectName, '高数');
    });

    test('added 补课：规则外日期新增一次', () {
      final sunday = DateTime(2026, 7, 12);
      final svc = ScheduleService(_nativeCalendar(
        overrides: const {
          '2026-07-12': OccurrenceOverride(
            added: true,
            customStart: '10:00',
            customEnd: '11:30',
          ),
        },
      ));
      final s = svc.scheduleFor(sunday);
      expect(s.lessons.single.start, const Duration(hours: 10));
      expect(s.lessons.single.end, const Duration(hours: 11, minutes: 30));
    });
  });

  group('周次范围', () {
    test('range 1–2：第 3 周不再上课', () {
      final svc = ScheduleService(_nativeCalendar(
        weeks: const WeekRule(fromWeek: 1, toWeek: 2),
      ));
      expect(svc.scheduleFor(monday).lessons.length, 1); // 第 1 周
      expect(
        svc.scheduleFor(monday.add(const Duration(days: 7))).lessons.length,
        1,
      ); // 第 2 周
      expect(
        svc.scheduleFor(monday.add(const Duration(days: 14))).isEmpty,
        true,
      ); // 第 3 周
    });

    test('include 显式周列表', () {
      final svc = ScheduleService(_nativeCalendar(
        weeks: const WeekRule(include: [2]),
      ));
      expect(svc.scheduleFor(monday).isEmpty, true); // 第 1 周
      expect(
        svc.scheduleFor(monday.add(const Duration(days: 7))).lessons.length,
        1,
      ); // 第 2 周
    });
  });

  group('冲突与空闲', () {
    test('conflicts 检测时间重叠', () {
      final svc = ScheduleService(_nativeCalendar(
        extraMeeting: const Meeting(
          id: 'm-overlap',
          weekday: 1,
          customStart: '09:00',
          customEnd: '10:00',
        ),
      ));
      expect(svc.conflicts(monday).length, 1); // 与 8:00–9:40 重叠
    });

    test('freeSlots 扣除已占用时段', () {
      final svc = ScheduleService(_nativeCalendar());
      final slots = svc.freeSlots(
        monday,
        from: const Duration(hours: 8),
        to: const Duration(hours: 12),
      );
      // 8:00–9:40 有课 → 空闲 9:40–12:00
      expect(slots.length, 1);
      expect(slots.single.start, const Duration(hours: 9, minutes: 40));
      expect(slots.single.end, const Duration(hours: 12));
    });
  });
}
