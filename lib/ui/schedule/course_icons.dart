import 'package:flutter/material.dart';

/// `CourseEvent.icon` 的可选值：稳定图标名 → Material 图标。
///
/// 图标名随档案 JSON 序列化持久：只可新增键，不要改动/删除已有键。
const Map<String, IconData> courseIcons = {
  'math': Icons.calculate_outlined,
  'chinese': Icons.menu_book_outlined,
  'english': Icons.translate,
  'physics': Icons.rocket_launch_outlined,
  'chemistry': Icons.science_outlined,
  'biology': Icons.eco_outlined,
  'history': Icons.history_edu_outlined,
  'geography': Icons.public_outlined,
  'politics': Icons.account_balance_outlined,
  'computer': Icons.computer_outlined,
  'music': Icons.music_note_outlined,
  'art': Icons.palette_outlined,
  'pe': Icons.directions_run,
  'lab': Icons.biotech_outlined,
  'club': Icons.groups_outlined,
  'selfstudy': Icons.edit_note_outlined,
};

/// 图标名 → 图标；未知名字（含空串）返回 null。
IconData? courseIcon(String name) => courseIcons[name];
