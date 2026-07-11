/// 宽容的 JSON 取值与时间解析工具。
///
/// ClassIsland 档案是 C#(Newtonsoft) 序列化的 PascalCase JSON，字段类型偶有
/// 不一致（bool/int 有时是字符串，时间既可能是 TimeSpan 也可能是 DateTime）。
/// 这里集中做防御式转换，让模型层的 `fromJson` 保持简洁。
library;

/// 从 [json] 中按顺序取第一个非空键（用于同时兼容 PascalCase / camelCase）。
dynamic pick(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k];
    if (v != null) return v;
  }
  return null;
}

bool asBool(dynamic v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return fallback;
}

int asInt(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

String asString(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  return v.toString();
}

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return <String, dynamic>{};
}

List<dynamic> asList(dynamic v) {
  if (v is List) return v;
  return const <dynamic>[];
}

/// 把 ClassIsland 的时刻解析成"距零点的时长"。
///
/// 兼容两种序列化：
/// - TimeSpan 字符串：`"08:00:00"`、`"1.08:00:00"`（含天）、`"08:00:00.500"`。
/// - DateTime 字符串：`"2023-01-01T08:00:00"`（仅取时刻部分）。
Duration? parseTimeOfDay(dynamic v) {
  if (v == null) return null;
  var s = v.toString().trim();
  if (s.isEmpty) return null;

  if (s.contains('T')) {
    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return Duration(hours: dt.hour, minutes: dt.minute, seconds: dt.second);
    }
    s = s.substring(s.indexOf('T') + 1);
  }

  final parts = s.split(':');
  if (parts.isEmpty) return null;

  var days = 0;
  var head = parts[0];
  // TimeSpan 里 "d.hh:mm:ss" 的天数部分（仅当后面还有 ':' 段时才当作天）。
  if (head.contains('.') && parts.length >= 2) {
    final dot = head.split('.');
    days = int.tryParse(dot[0]) ?? 0;
    head = dot.length > 1 ? dot[1] : '0';
  }
  final hours = int.tryParse(head) ?? 0;
  final minutes = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final seconds =
      parts.length > 2 ? int.tryParse(parts[2].split('.').first) ?? 0 : 0;

  return Duration(days: days, hours: hours, minutes: minutes, seconds: seconds);
}

/// 把时长回写成 ClassIsland 的 TimeSpan 文本 `HH:mm:ss`。
String durationToTimeSpan(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = two(d.inHours);
  final m = two(d.inMinutes.remainder(60));
  final s = two(d.inSeconds.remainder(60));
  return '$h:$m:$s';
}
