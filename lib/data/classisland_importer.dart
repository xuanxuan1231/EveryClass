import 'dart:convert';

import '../models/profile.dart';

/// 导入失败时抛出，`message` 面向用户。
class ImportException implements Exception {
  final String message;
  ImportException(this.message);
  @override
  String toString() => message;
}

/// 把 ClassIsland 档案 JSON 解析为 [Profile]。
///
/// 解析本身宽容（见 `models/*` 与 `util/coerce.dart`）；这里负责入口校验与
/// 友好的错误信息。
class ClassIslandImporter {
  static Profile parse(String jsonText) {
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
}
