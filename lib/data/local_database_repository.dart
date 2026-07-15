import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/database.dart';
import '../models/profile.dart';
import 'classisland_converter.dart';
import 'database_repository.dart';

/// 把数据库以 JSON 文件形式存到应用文档目录（`database.json`）。
///
/// 首次运行会尝试从旧版 `profile.json`（ClassIsland 中间模型）一次性迁移。
class LocalDatabaseRepository implements DatabaseRepository {
  static const String _fileName = 'database.json';
  static const String _legacyFileName = 'profile.json';

  File? _cachedFile;

  Future<Directory> _dir() => getApplicationDocumentsDirectory();

  Future<File> _file() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final dir = await _dir();
    final file = File('${dir.path}/$_fileName');
    _cachedFile = file;
    return file;
  }

  @override
  Future<Database?> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final text = await file.readAsString();
        if (text.trim().isNotEmpty) {
          final decoded = jsonDecode(text);
          if (decoded is Map) {
            return Database.fromJson(
              decoded.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
        }
      }
      // 迁移：旧 profile.json → 新模型。
      final migrated = await _migrateLegacy();
      if (migrated != null) {
        await save(migrated);
        return migrated;
      }
      return null;
    } catch (_) {
      // 读取/解析失败时当作"无数据"，避免启动崩溃。
      return null;
    }
  }

  Future<Database?> _migrateLegacy() async {
    try {
      final dir = await _dir();
      final legacy = File('${dir.path}/$_legacyFileName');
      if (!await legacy.exists()) return null;
      final text = await legacy.readAsString();
      if (text.trim().isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final profile =
          Profile.fromJson(decoded.map((k, v) => MapEntry(k.toString(), v)));
      if (profile.subjects.isEmpty &&
          profile.timeLayouts.isEmpty &&
          profile.classPlans.isEmpty) {
        return null;
      }
      return ClassIslandConverter.toDatabase(profile);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Database database) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(database.toJson()));
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
