import 'package:everyclass/models/subject.dart';
import 'package:everyclass/models/time_layout.dart';
import 'package:everyclass/models/week_rule.dart';
import 'package:everyclass/models/alert.dart';
import 'package:everyclass/models/meeting.dart';
import 'package:everyclass/util/coerce.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('coerce', () {
    test('asBool 宽容处理各种写法', () {
      expect(asBool(true), true);
      expect(asBool('true'), true);
      expect(asBool('1'), true);
      expect(asBool(1), true);
      expect(asBool('false'), false);
      expect(asBool(0), false);
      expect(asBool(null), false);
    });

    test('parseTimeOfDay 支持 TimeSpan 与 DateTime 两种写法', () {
      expect(parseTimeOfDay('08:00:00'), const Duration(hours: 8));
      expect(
        parseTimeOfDay('2023-01-01T08:45:30'),
        const Duration(hours: 8, minutes: 45, seconds: 30),
      );
      expect(
        parseTimeOfDay('08:45:00.500'),
        const Duration(hours: 8, minutes: 45),
      );
      expect(parseTimeOfDay(''), isNull);
      expect(parseTimeOfDay(null), isNull);
    });

    test('durationToTimeSpan 回写', () {
      expect(
        durationToTimeSpan(const Duration(hours: 8, minutes: 5, seconds: 3)),
        '08:05:03',
      );
    });
  });

  group('Subject', () {
    test('走班教室通过 AttachedObjects 往返', () {
      final s = Subject.fromJson({
        'Name': '数学',
        'Initial': '数',
        'IsOutDoor': false,
        'AttachedObjects': {'everyclass.room': 'A101'},
      });
      expect(s.name, '数学');
      expect(s.defaultRoom, 'A101');

      final json = s.toJson();
      final attached = json['AttachedObjects'] as Map<String, dynamic>;
      expect(attached['everyclass.room'], 'A101');

      // 二次解析保持一致
      expect(Subject.fromJson(json).defaultRoom, 'A101');
    });
  });

  group('TimeLayoutItem', () {
    test('lessonItems 只保留上课时间点', () {
      final layout = TimeLayout.fromJson({
        'Name': '标准',
        'Layouts': [
          {'StartTime': '08:00:00', 'EndTime': '08:45:00', 'TimeType': 0},
          {'StartTime': '08:45:00', 'EndTime': '08:55:00', 'TimeType': 1},
          {'StartTime': '08:55:00', 'EndTime': '09:40:00', 'TimeType': 0},
        ],
      });
      expect(layout.items.length, 3);
      expect(layout.lessonItems.length, 2);
      expect(layout.lessonItems.first.start, const Duration(hours: 8));
    });
  });

  group('WeekRule', () {
    test('每周规则命中全部周', () {
      expect(WeekRule.every.matches(1), true);
      expect(WeekRule.every.matches(17), true);
    });

    test('单双周：interval=2', () {
      const odd = WeekRule(interval: 2, offset: 0); // 单周（第1,3,5…）
      const even = WeekRule(interval: 2, offset: 1); // 双周（第2,4,6…）
      expect(odd.matches(1), true);
      expect(odd.matches(2), false);
      expect(even.matches(2), true);
      expect(even.matches(1), false);
    });

    test('周次范围 + 显式周列表', () {
      const ranged = WeekRule(fromWeek: 3, toWeek: 5);
      expect(ranged.matches(2), false);
      expect(ranged.matches(4), true);
      expect(ranged.matches(6), false);

      const listed = WeekRule(include: [1, 3, 5]);
      expect(listed.matches(3), true);
      expect(listed.matches(4), false);
    });

    test('JSON 往返', () {
      const r = WeekRule(interval: 2, offset: 1, fromWeek: 2, toWeek: 16);
      final again = WeekRule.fromJson(r.toJson());
      expect(again.interval, 2);
      expect(again.offset, 1);
      expect(again.fromWeek, 2);
      expect(again.toWeek, 16);
    });
  });

  group('Alert', () {
    test('课前 5 分钟 → -PT5M 往返', () {
      final a = Alert.beforeStart(const Duration(minutes: 5));
      final json = a.toJson();
      expect((json['trigger'] as Map)['offset'], '-PT5M');
      final again = Alert.fromJson(json);
      expect(again.offset, const Duration(minutes: -5));
      expect(again.relativeToEnd, false);
    });

    test('parseIso8601Duration 解析时/分/秒', () {
      expect(parseIso8601Duration('PT1H30M'),
          const Duration(hours: 1, minutes: 30));
      expect(parseIso8601Duration('-PT45S'), const Duration(seconds: -45));
    });
  });

  group('Meeting', () {
    test('自定义时刻优先，序列化不写节次', () {
      const m = Meeting(
        id: 'm',
        weekday: 1,
        customStart: '19:30',
        customEnd: '21:00',
      );
      expect(m.usesCustomTime, true);
      final json = m.toJson();
      expect(json['customStart'], '19:30');
      expect(json.containsKey('startPeriod'), false);
      expect(Meeting.fromJson(json).customEnd, '21:00');
    });

    test('引用节次时序列化不写自定义时刻', () {
      const m = Meeting(id: 'm', weekday: 3, startPeriod: 1, endPeriod: 2);
      final json = m.toJson();
      expect(json['startPeriod'], 1);
      expect(json['endPeriod'], 2);
      expect(json.containsKey('customStart'), false);
    });
  });
}
