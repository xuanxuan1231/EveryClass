import 'package:flutter/material.dart';

import '../../models/resolved_lesson.dart';

/// 课程卡片配色：优先用课程自带颜色（`#RRGGBB`），否则按课程 ID 从调色板
/// 稳定取色——同一门课在任何页面、任何会话永远同色。

/// 解析 `#RRGGBB` / `#AARRGGBB`；失败返回 null。
Color? parseHexColor(String hex) {
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final v = int.tryParse(s, radix: 16);
  return v == null ? null : Color(v);
}

/// Color → `#RRGGBB`（丢弃透明度），与 `CourseEvent.color` 的存储格式一致。
String colorToHex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// WakeUp 风格调色板：饱和度适中、白字可读，明暗主题下都成立。
/// 也是课程编辑器里的可选色板。
const List<Color> lessonPalette = [
  Color(0xFFEF5350), // 红
  Color(0xFFEC407A), // 粉
  Color(0xFFAB47BC), // 紫
  Color(0xFF7E57C2), // 深紫
  Color(0xFF5C6BC0), // 靛蓝
  Color(0xFF1E88E5), // 蓝
  Color(0xFF00ACC1), // 青
  Color(0xFF26A69A), // 蓝绿
  Color(0xFF43A047), // 绿
  Color(0xFFF57C00), // 橙
  Color(0xFFFF7043), // 橘红
  Color(0xFF78909C), // 蓝灰
];

/// FNV-1a 哈希：跨平台/跨会话稳定（`String.hashCode` 无此保证）。
int _stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// 未自选颜色时的自动取色（按稳定键从调色板取）。
Color autoCourseColor(String key) =>
    lessonPalette[_stableHash(key) % lessonPalette.length];

/// 课程展示色：自选色 [hexColor] 优先，否则按 [id]（回退 [title]）自动取色。
/// 与 [lessonColor] 同一套规则，供课程列表/编辑器在没有 [ResolvedLesson]
/// 时使用。
Color courseDisplayColor(String id, String title, String hexColor) {
  return parseHexColor(hexColor) ?? autoCourseColor(id.isNotEmpty ? id : title);
}

Color lessonColor(ResolvedLesson lesson) {
  final own = parseHexColor(lesson.color);
  if (own != null) return own;
  final key =
      lesson.subjectId.isNotEmpty ? lesson.subjectId : lesson.subjectName;
  return autoCourseColor(key);
}
