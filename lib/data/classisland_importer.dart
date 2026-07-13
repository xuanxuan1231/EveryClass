import 'dart:convert';

import '../models/database.dart';
import '../models/profile.dart';
import 'classisland_converter.dart';

/// 导入失败时抛出，`message` 面向用户。
class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// 把 ClassIsland 档案 JSON 解析并**转换**成新模型的 [Database]（仅导入，不导出）。
///
/// 解析本身宽容（见 `models/*` 与 `util/coerce.dart`）；这里负责入口校验、友好的
/// 错误信息，以及经 [ClassIslandConverter] 转成 Calendar。
class ClassIslandImporter {
  /// 解析为 ClassIsland 中间模型（内部/测试用）。
  static Profile parseProfile(String jsonText) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (e) {
      throw ImportException('不是合法的 JSON 档案。');
    }
    if (decoded is! Map) {
      throw ImportException('档案格式不对：根节点应为对象。');
    }
    final json = decoded.map((k, v) => MapEntry(k.toString(), v));
    final profile = Profile.fromJson(json);

    if (profile.subjects.isEmpty &&
        profile.timeLayouts.isEmpty &&
        profile.classPlans.isEmpty) {
      throw ImportException(
        '未在档案中找到 Subjects / TimeLayouts / ClassPlans，可能不是 ClassIsland 档案。',
      );
    }
    return profile;
  }

  /// 解析并转换为新模型的 [Database]。
  static Database parse(String jsonText, {DateTime? firstWeekStart}) {
    final profile = parseProfile(jsonText);
    return ClassIslandConverter.toDatabase(
      profile,
      firstWeekStart: firstWeekStart,
    );
  }
}
