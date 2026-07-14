/// [WeekRule] 与「显式周次集合」的互转与中文摘要，供课程编辑器的周次选择用。
///
/// 编辑器让用户在 1..N 的网格里勾选周次；保存时用 [weekRuleFromWeeks] 把勾选
/// 结果规约成最紧凑的规则（连续区间 / 单双周 / 显式列表），展示时用
/// [weeksOfRule] 反向展开、[weekRuleLabel] 生成摘要。
library;

import 'dart:math' as math;

import '../models/calendar.dart';
import '../models/week_rule.dart';

/// 规则在 1..[totalWeeks] 内命中的周次集合。
Set<int> weeksOfRule(WeekRule rule, int totalWeeks) {
  return {
    for (var w = 1; w <= totalWeeks; w++)
      if (rule.matches(w)) w,
  };
}

/// 周次网格的格数：默认 [defaultWeeks]（[Calendar.defaultWeekCount]），且不小于
/// [rule] 已引用的最大周，保证已有规则完整可见。学期无固定周数，网格只是给
/// 用户勾选的一个足够大的范围。
int weekGridCount(WeekRule rule, {int defaultWeeks = Calendar.defaultWeekCount}) {
  var maxRef = rule.toWeek;
  for (final w in rule.include) {
    maxRef = math.max(maxRef, w);
  }
  return math.max(defaultWeeks, maxRef);
}

/// 把勾选的周次集合规约成最紧凑的 [WeekRule]：
/// 连续区间 → 每周 + range；公差为 2 的等差 → 单/双周 + range；
/// 其余 → include 显式列表。空集合按「每周」处理（调用方应避免传空）。
WeekRule weekRuleFromWeeks(Iterable<int> weeks) {
  final sorted = weeks.where((w) => w > 0).toSet().toList()..sort();
  if (sorted.isEmpty) return WeekRule.every;
  final from = sorted.first;
  final to = sorted.last;
  if (sorted.length == to - from + 1) {
    return WeekRule(fromWeek: from, toWeek: to);
  }
  var isStep2 = true;
  for (var i = 0; i + 1 < sorted.length; i++) {
    if (sorted[i + 1] - sorted[i] != 2) {
      isStep2 = false;
      break;
    }
  }
  if (isStep2) {
    // matches 判定 (week-1) % 2 == offset，故奇数周 offset=0（单周）。
    return WeekRule(
      interval: 2,
      offset: (from - 1) % 2,
      fromWeek: from,
      toWeek: to,
    );
  }
  return WeekRule(fromWeek: from, toWeek: to, include: sorted);
}

/// 人读摘要：「每周」「第 1-16 周」「第 1-16 周 · 单周」「第 1、3、7 周」等。
String weekRuleLabel(WeekRule rule) {
  if (rule.include.isNotEmpty) {
    return '第 ${rule.include.join('、')} 周';
  }
  final String range;
  if (rule.toWeek > 0) {
    range = rule.fromWeek == rule.toWeek
        ? '第 ${rule.fromWeek} 周'
        : '第 ${rule.fromWeek}-${rule.toWeek} 周';
  } else if (rule.fromWeek > 1) {
    range = '第 ${rule.fromWeek} 周起';
  } else {
    range = '每周';
  }
  if (rule.interval == 2) {
    // 学期周从 1 数起：offset 0 命中 1、3、5…（单周），offset 1 命中双周。
    final parity = rule.offset % 2 == 0 ? '单周' : '双周';
    return range == '每周' ? parity : '$range · $parity';
  }
  if (rule.interval > 2) {
    final rotate = '每 ${rule.interval} 周轮换（第 ${rule.offset + 1} 轮）';
    return range == '每周' ? rotate : '$range · $rotate';
  }
  return range;
}
