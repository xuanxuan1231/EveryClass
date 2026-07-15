import 'package:everyclass/models/week_rule.dart';
import 'package:everyclass/util/week_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('weekRuleFromWeeks 规约', () {
    test('连续区间 → 每周 + range', () {
      final r = weekRuleFromWeeks([1, 2, 3, 4]);
      expect(r.interval, 1);
      expect(r.fromWeek, 1);
      expect(r.toWeek, 4);
      expect(r.include, isEmpty);
    });

    test('奇数周 → 单周（interval 2, offsets [0]）', () {
      final r = weekRuleFromWeeks([1, 3, 5, 7]);
      expect(r.interval, 2);
      expect(r.offsets, [0]);
      expect(r.fromWeek, 1);
      expect(r.toWeek, 7);
      expect(r.include, isEmpty);
    });

    test('偶数周 → 双周（interval 2, offsets [1]）', () {
      final r = weekRuleFromWeeks([2, 4, 6]);
      expect(r.interval, 2);
      expect(r.offsets, [1]);
      expect(r.fromWeek, 2);
      expect(r.toWeek, 6);
    });

    test('每 3 周中的第 1 周 → 轮换规则', () {
      final r = weekRuleFromWeeks([1, 4, 7, 10]);
      expect(r.interval, 3);
      expect(r.offsets, [0]);
      expect(r.fromWeek, 1);
      expect(r.toWeek, 10);
      expect(r.include, isEmpty);
    });

    test('每 3 周中的第 1、2 周 → 多 offset 轮换规则', () {
      final r = weekRuleFromWeeks([1, 2, 4, 5, 7, 8]);
      expect(r.interval, 3);
      expect(r.offsets, [0, 1]);
      expect(r.fromWeek, 1);
      expect(r.toWeek, 8);
      expect(r.include, isEmpty);
    });

    test('不足两个完整周期不当作轮换 → include 显式列表', () {
      final r = weekRuleFromWeeks([1, 4]);
      expect(r.include, [1, 4]);
    });

    test('无规律散列 → include 显式列表', () {
      final r = weekRuleFromWeeks([1, 2, 5]);
      expect(r.include, [1, 2, 5]);
      expect(r.fromWeek, 1);
      expect(r.toWeek, 5);
    });

    test('单个周 → 单周范围', () {
      final r = weekRuleFromWeeks([5]);
      expect(r.interval, 1);
      expect(r.fromWeek, 5);
      expect(r.toWeek, 5);
      expect(r.include, isEmpty);
    });

    test('空集合 → 每周（调用方应避免传空）', () {
      final r = weekRuleFromWeeks(const <int>[]);
      expect(r.fromWeek, 1);
      expect(r.toWeek, 0);
      expect(r.interval, 1);
    });
  });

  test('weeksOfRule ∘ weekRuleFromWeeks 无损往返', () {
    const cases = [
      {1, 2, 3},
      {1, 3, 5, 7, 9},
      {2, 4, 6, 8},
      {1, 4, 9, 16},
      {7},
      {3, 4, 5, 10, 11},
      {1, 4, 7, 10, 13},
      {2, 3, 6, 7, 10, 11},
      {5, 9, 13, 17},
    ];
    for (final weeks in cases) {
      expect(
        weeksOfRule(weekRuleFromWeeks(weeks), 20),
        weeks,
        reason: '往返失败：$weeks',
      );
    }
  });

  group('weekRuleLabel', () {
    test('每周', () {
      expect(weekRuleLabel(WeekRule.every), '每周');
    });

    test('范围', () {
      expect(weekRuleLabel(const WeekRule(fromWeek: 1, toWeek: 16)),
          '第 1-16 周');
      expect(weekRuleLabel(const WeekRule(fromWeek: 5, toWeek: 5)), '第 5 周');
      expect(weekRuleLabel(const WeekRule(fromWeek: 3)), '第 3 周起');
    });

    test('单双周', () {
      expect(
        weekRuleLabel(
            const WeekRule(interval: 2, offsets: [0], fromWeek: 1, toWeek: 15)),
        '第 1-15 周 · 单周',
      );
      expect(
        weekRuleLabel(
            const WeekRule(interval: 2, offsets: [1], fromWeek: 2, toWeek: 16)),
        '第 2-16 周 · 双周',
      );
      expect(weekRuleLabel(const WeekRule(interval: 2, offsets: [0])), '单周');
    });

    test('显式列表与多周轮换', () {
      expect(
        weekRuleLabel(
            const WeekRule(fromWeek: 1, toWeek: 9, include: [1, 4, 9])),
        '第 1、4、9 周',
      );
      expect(
        weekRuleLabel(const WeekRule(interval: 3, offsets: [1])),
        '每 3 周中的第 2 周',
      );
      expect(
        weekRuleLabel(const WeekRule(
            interval: 3, offsets: [0, 1], fromWeek: 1, toWeek: 12)),
        '第 1-12 周 · 每 3 周中的第 1、2 周',
      );
      // 周期内序数相对范围起点：从第 2 周起、相位 1（=起始周本身）→ 第 1 周。
      expect(
        weekRuleLabel(const WeekRule(interval: 3, offsets: [1], fromWeek: 2)),
        '第 2 周起 · 每 3 周中的第 1 周',
      );
    });

    test('相位覆盖整个周期视作每周', () {
      expect(
        weekRuleLabel(const WeekRule(
            interval: 2, offsets: [0, 1], fromWeek: 1, toWeek: 8)),
        '第 1-8 周',
      );
    });
  });

  test('weekGridCount：默认 20，随已引用的最大周放大', () {
    expect(weekGridCount(WeekRule.every), 20);
    expect(weekGridCount(WeekRule.every, defaultWeeks: 18), 18);
    expect(weekGridCount(const WeekRule(toWeek: 25)), 25);
    expect(weekGridCount(const WeekRule(include: [22])), 22);
  });
}
