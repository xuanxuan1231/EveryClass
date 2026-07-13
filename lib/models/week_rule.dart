import '../util/coerce.dart';

/// 周次规则：覆盖「每周 / 单双周 / 周次范围 / N 周轮换 / 显式周列表」。
///
/// 判定第 [week]（1-based 学期周）是否生效：
/// `range` 命中且（`include` 非空 → `week ∈ include`；否则
/// `(week - 1) % interval == offset`）。可无损转 JSCalendar `RecurrenceRule`。
class WeekRule {
  /// 轮换周期长度：1=每周；2=单/双周；N=N 周轮换。对应 RRULE INTERVAL。
  final int interval;

  /// 在周期内第几周生效，0-based（单周=0，双周=1）。
  final int offset;

  /// 周次范围（含，1-based 学期周）。
  final int fromWeek;

  /// 周次范围上界（含）；<=0 表示不设上界。
  final int toWeek;

  /// 显式周列表；非空时忽略 [interval]/[offset]。对应 RDATE。
  final List<int> include;

  const WeekRule({
    this.interval = 1,
    this.offset = 0,
    this.fromWeek = 1,
    this.toWeek = 0,
    this.include = const [],
  });

  /// 每周生效、不限范围的默认规则。
  static const WeekRule every = WeekRule();

  bool matches(int week) {
    if (week < fromWeek) return false;
    if (toWeek > 0 && week > toWeek) return false;
    if (include.isNotEmpty) return include.contains(week);
    final total = interval <= 0 ? 1 : interval;
    return (week - 1) % total == offset % total;
  }

  WeekRule copyWith({
    int? interval,
    int? offset,
    int? fromWeek,
    int? toWeek,
    List<int>? include,
  }) {
    return WeekRule(
      interval: interval ?? this.interval,
      offset: offset ?? this.offset,
      fromWeek: fromWeek ?? this.fromWeek,
      toWeek: toWeek ?? this.toWeek,
      include: include ?? this.include,
    );
  }

  factory WeekRule.fromJson(Map<String, dynamic> json) {
    final range = asMap(pick(json, ['range', 'Range']));
    return WeekRule(
      interval: asInt(pick(json, ['interval', 'Interval']), fallback: 1),
      offset: asInt(pick(json, ['offset', 'Offset'])),
      fromWeek: asInt(
        pick(range, ['from', 'From']) ?? pick(json, ['fromWeek']),
        fallback: 1,
      ),
      toWeek: asInt(pick(range, ['to', 'To']) ?? pick(json, ['toWeek'])),
      include: asList(pick(json, ['include', 'Include']))
          .map((e) => asInt(e))
          .where((e) => e > 0)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'interval': interval,
        'offset': offset,
        'range': {'from': fromWeek, if (toWeek > 0) 'to': toWeek},
        if (include.isNotEmpty) 'include': include,
      };
}
