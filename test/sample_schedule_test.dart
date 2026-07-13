import 'dart:convert';
import 'dart:io';

import 'package:everyclass/data/classisland_importer.dart';
import 'package:everyclass/models/database.dart';
import 'package:everyclass/services/schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用仓库根的 sample_schedule.json（一份"有课"的完整 ClassIsland 档案）端到端验证
/// 导入转换 + 调度引擎 + 新模型 JSON 往返。
void main() {
  test('sample_schedule.json 导入并解析出整天课表', () {
    final text = File('sample_schedule.json').readAsStringSync();
    final db = ClassIslandImporter.parse(text);
    final cal = db.selected!;
    expect(cal.courses.length, 8);
    expect(cal.bellSchedules.length, 1);

    final svc = ScheduleService(cal);
    final monday = DateTime(2026, 7, 6); // 周一
    expect(monday.weekday, DateTime.monday);

    final day = svc.scheduleFor(monday);
    expect(day.lessons.length, 8); // 8 节课，课间被跳过
    expect(day.lessons.first.subjectName, '语文');
    expect(day.lessons.first.period, 1);
    expect(day.lessons.first.start, const Duration(hours: 8));
    expect(day.lessons.last.end, const Duration(hours: 17, minutes: 30));

    // 走班教室：物理教室来自 Subject 的 AttachedObjects。
    final physics = day.lessons.firstWhere((l) => l.subjectName == '物理');
    expect(physics.room, '实验楼302');

    // 7 天都有课，任何一天真机测试都能看到内容。
    for (var d = 0; d < 7; d++) {
      final s = svc.scheduleFor(monday.add(Duration(days: d)));
      expect(s.lessons.length, 8);
    }
  });

  test('新模型 JSON 无损往返：再解析后课表一致', () {
    final text = File('sample_schedule.json').readAsStringSync();
    final db = ClassIslandImporter.parse(text);
    final again = Database.fromJson(
      (jsonDecode(jsonEncode(db.toJson())) as Map)
          .map((k, v) => MapEntry(k.toString(), v)),
    );

    final monday = DateTime(2026, 7, 6);
    final before = ScheduleService(db.selected!).scheduleFor(monday);
    final after = ScheduleService(again.selected!).scheduleFor(monday);
    expect(after.lessons.length, before.lessons.length);
    for (var i = 0; i < before.lessons.length; i++) {
      expect(after.lessons[i].subjectName, before.lessons[i].subjectName);
      expect(after.lessons[i].start, before.lessons[i].start);
      expect(after.lessons[i].end, before.lessons[i].end);
      expect(after.lessons[i].room, before.lessons[i].room);
    }
  });
}
