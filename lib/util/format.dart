/// UI 用到的轻量时间格式化（不依赖 intl 的 locale 初始化）。
library;

const List<String> _weekdayCn = ['一', '二', '三', '四', '五', '六', '日'];

String weekdayCn(DateTime d) => '周${_weekdayCn[d.weekday - 1]}';

String ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 距零点的时长 → `HH:mm`。
String hm(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// 倒计时格式：>1h 显示 `H:mm:ss`，否则 `mm:ss`。
String fmtCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// 提前量（秒）→ 中文时长：整分「N 分钟」，含秒「N 分 S 秒」，不足一分「S 秒」。
String leadCn(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m == 0) return '$s 秒';
  if (s == 0) return '$m 分钟';
  return '$m 分 $s 秒';
}
