import 'package:everyclass/models/subject.dart';
import 'package:everyclass/models/time_layout.dart';
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
}
