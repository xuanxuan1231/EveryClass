import 'dart:convert';

import 'package:everyclass/data/classisland_importer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 取自真实 Default.json 的结构（空课表：有 Subjects，无 TimeLayouts/ClassPlans）。
const _emptyProfileJson = '''
{
  "Name": "",
  "TimeLayouts": {},
  "ClassPlans": {},
  "Subjects": {
    "97d0bf3f-137f-4f8a-87d6-ff387063bbd3": {"Name":"语文","Initial":"语","TeacherName":"","IsOutDoor":false,"AttachedObjects":{},"IsActive":false},
    "66d1c380-d292-46e1-86d5-d403e2a4f200": {"Name":"信息技术","Initial":"信","TeacherName":"","IsOutDoor":true,"AttachedObjects":{},"IsActive":false}
  },
  "ClassPlanGroups": {
    "acaf4ef0-e261-4262-b941-34ea93cb4369": {"Name":"默认","IsGlobal":false,"IsActive":false}
  },
  "SelectedClassPlanGroupId": "acaf4ef0-e261-4262-b941-34ea93cb4369",
  "Id": "3b7eb175-d2b4-4170-ad8d-959c7b08cc34",
  "OrderedSchedules": {}
}
''';

void main() {
  group('ClassIslandImporter', () {
    test('解析空课表：科目与群组正确，高级层进 extra 保留', () {
      final profile = ClassIslandImporter.parse(_emptyProfileJson);
      expect(profile.subjects.length, 2);
      expect(
        profile.subjects['97d0bf3f-137f-4f8a-87d6-ff387063bbd3']!.name,
        '语文',
      );
      expect(
        profile.subjects['66d1c380-d292-46e1-86d5-d403e2a4f200']!.isOutDoor,
        true,
      );
      expect(profile.timeLayouts, isEmpty);
      expect(profile.classPlanGroups.length, 1);
      expect(
        profile.selectedClassPlanGroupId,
        'acaf4ef0-e261-4262-b941-34ea93cb4369',
      );
      // 未识别的顶层字段（如 OrderedSchedules）保留在 extra 里
      expect(profile.extra.containsKey('OrderedSchedules'), true);
    });

    test('往返：toJson 后再解析科目与保留字段不丢', () {
      final profile = ClassIslandImporter.parse(_emptyProfileJson);
      final again = ClassIslandImporter.parse(jsonEncode(profile.toJson()));
      expect(again.subjects.length, 2);
      expect(again.extra.containsKey('OrderedSchedules'), true);
    });

    test('非法 JSON 抛 ImportException', () {
      expect(
        () => ClassIslandImporter.parse('not json'),
        throwsA(isA<ImportException>()),
      );
    });

    test('空对象抛 ImportException', () {
      expect(
        () => ClassIslandImporter.parse('{}'),
        throwsA(isA<ImportException>()),
      );
    });
  });
}
