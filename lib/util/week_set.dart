/// [WeekRule] 与「显式周次集合」的互转与中文摘要，供课程编辑器的周次选择用。
///
/// 编辑器让用户在 1..N 的网格里勾选周次；保存时用 [weekRuleFromWeeks] 把勾选
/// 结果规约成最紧凑的规则（连续区间 / N 周轮换 / 显式列表），展示时用
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
/// 连续区间 → 每周 + range；周期性（含单双周、每 N 周中若干周）→ 轮换 + range；
/// 其余 → include 显式列表。空集合按「每周」处理（调用方应避免传空）。
WeekRule weekRuleFromWeeks(Iterable<int> weeks) {
  final sorted = weeks.where((w) => w > 0).toSet().toList()..sort();
  if (sorted.isEmpty) return WeekRule.every;
  final from = sorted.first;
  final to = sorted.last;
  final span = to - from + 1;
  if (sorted.length == span) {
    return WeekRule(fromWeek: from, toWeek: to);
  }
  // 识别 k 周轮换（k 从小到大取最紧凑者）：勾选集合恰为 [from..to] 内相位
  // 落在某组 offsets 的全部周。要求范围至少覆盖两个完整周期，避免把偶然的
  // 散点当成轮换。
  final selected = sorted.toSet();
  for (var k = 2; 2 * k <= span; k++) {
    final offsets = {for (final w in sorted) (w - 1) % k};
    if (offsets.length >= k) continue;
    final expanded = {
      for (var w = from; w <= to; w++)
        if (offsets.contains((w - 1) % k)) w,
    };
    if (expanded.length == selected.length && expanded.containsAll(selected)) {
      return WeekRule(
        interval: k,
        offsets: offsets.toList()..sort(),
        fromWeek: from,
        toWeek: to,
      );
    }
  }
  return WeekRule(fromWeek: from, toWeek: to, include: sorted);
}

/// 规则在周期内的相位集合（对 [WeekRule.interval] 取模去重）；周期 <=1 或
/// 相位覆盖整个周期视作「每周」（返回空集合表示无轮换语义）。
Set<int> rotationPhases(WeekRule rule) {
  final total = rule.interval;
  if (total <= 1) return const {};
  final phases = {for (final o in rule.offsets) o % total};
  return phases.length >= total ? const {} : phases;
}

/// 人读摘要：「每周」「第 1-16 周」「第 1-16 周 · 单周」「第 1、3、7 周」
/// 「第 1-16 周 · 每 3 周中的第 1、2 周」等。轮换的周期内序数按 [WeekRule.fromWeek]
/// 所在周期起点计（第 1 周 = 范围起始周），与选择器展示一致。
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
  final phases = rotationPhases(rule);
  if (phases.isEmpty) return range;
  final total = rule.interval;
  final String rotate;
  if (total == 2 && phases.length == 1) {
    // 学期周从 1 数起：相位 0 命中 1、3、5…（单周），相位 1 命中双周。
    rotate = phases.single == 0 ? '单周' : '双周';
  } else {
    final ordinals = [
      for (final p in phases) ((p - (rule.fromWeek - 1)) % total + total) % total + 1,
    ]..sort();
    rotate = '每 $total 周中的第 ${ordinals.join('、')} 周';
  }
  return range == '每周' ? rotate : '$range · $rotate';
}
