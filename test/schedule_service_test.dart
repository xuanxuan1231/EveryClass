import 'package:everyclass/data/classisland_importer.dart';
import 'package:everyclass/services/schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 合成的"有课"档案：周一两节（语文、数学），中间一节课间。
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

void main() {
  final monday = DateTime(2026, 7, 6); // 2026-07-06 是周一

  test('前置断言：2026-07-06 是周一', () {
    expect(monday.weekday, DateTime.monday);
  });

  group('scheduleFor', () {
    final svc = ScheduleService(ClassIslandImporter.parse(_populated));

    test('周一两节课，跳过课间，节次连续', () {
      final s = svc.scheduleFor(monday);
      expect(s.lessons.length, 2);
      expect(s.lessons[0].subjectName, '语文');
      expect(s.lessons[0].period, 1);
      expect(s.lessons[0].start, const Duration(hours: 8));
      expect(s.lessons[1].subjectName, '数学');
      expect(s.lessons[1].period, 2);
      expect(s.lessons[1].start, const Duration(hours: 8, minutes: 55));
    });

    test('教室解析：ClassInfo.room 覆盖 Subject.defaultRoom', () {
      final s = svc.scheduleFor(monday);
      expect(s.lessons[0].room, ''); // 语文无教室
      expect(s.lessons[1].room, 'B203'); // 数学 B203 覆盖科目默认 A101
    });

    test('非上课日无课', () {
      expect(svc.scheduleFor(monday.add(const Duration(days: 1))).isEmpty, true);
    });
  });

  group('current/next', () {
    final svc = ScheduleService(ClassIslandImporter.parse(_populated));

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
    final profile = ClassIslandImporter.parse(_alternating);
    final tuesdayW0 = DateTime(2026, 7, 7); // 第 0 周周二（单周序=1）
    final tuesdayW1 = DateTime(2026, 7, 14); // 第 1 周周二（双周序=2）

    test('前置断言：两天都是周二', () {
      expect(tuesdayW0.weekday, DateTime.tuesday);
      expect(tuesdayW1.weekday, DateTime.tuesday);
    });

    test('学期起始=第0周周一 → 单周选语文、双周选数学', () {
      final svc = ScheduleService(profile, termStart: monday);
      expect(svc.scheduleFor(tuesdayW0).lessons.single.subjectName, '语文');
      expect(svc.scheduleFor(tuesdayW1).lessons.single.subjectName, '数学');
    });

    test('未设学期起始日 → 不过滤轮换也不崩溃', () {
      final svc = ScheduleService(profile);
      expect(svc.scheduleFor(tuesdayW0).lessons.length, 1);
    });
  });
}
