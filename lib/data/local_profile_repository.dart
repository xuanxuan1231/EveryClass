import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/profile.dart';
import 'profile_repository.dart';

/// 把档案以 JSON 文件形式存到应用文档目录。
class LocalProfileRepository implements ProfileRepository {
  static const String _fileName = 'profile.json';

  File? _cachedFile;

  Future<File> _file() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_fileName');
    _cachedFile = file;
    return file;
  }

  @override
  Future<Profile?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return Profile.fromJson(decoded.map((k, v) => MapEntry(k.toString(), v)));
    } catch (_) {
      // 读取/解析失败时当作"无档案"，避免启动崩溃。
      return null;
    }
  }

  @override
  Future<void> save(Profile profile) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(profile.toJson()));
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
