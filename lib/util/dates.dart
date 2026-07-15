/// 日历翻页与日期比较的小工具（无 UI 依赖）。
///
/// 日/周视图用「无限翻页」的 PageView：页码 = 距锚点 [pageEpoch] 的天数/周数。
/// 锚点取 2000-01-03（周一），保证本世纪任意日期的页码非负，可双向滑动。
library;

/// 翻页锚点：2000-01-03，周一。
final DateTime pageEpoch = DateTime(2000, 1, 3);

/// 去掉时刻，只留日期。
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 该日所在周的周一（周一=1，对齐 `DateTime.weekday`）。
DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 日期 → 日页码。用小时数取整，避免夏令时导致的 ±1 偏差。
int dayPageOf(DateTime d) =>
    (dateOnly(d).difference(pageEpoch).inHours / 24).round();

/// 日页码 → 日期。走构造器的日期归一化，不做时长加法（夏令时安全）。
DateTime dayFromPage(int page) => DateTime(2000, 1, 3 + page);

/// 日期 → 该日所在周的周页码。
int weekPageOf(DateTime d) =>
    (mondayOf(d).difference(pageEpoch).inHours / 24).round() ~/ 7;

/// 周页码 → 该周周一。
DateTime mondayFromPage(int page) => DateTime(2000, 1, 3 + page * 7);
