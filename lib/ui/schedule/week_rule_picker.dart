import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/calendar.dart';
import '../../models/week_rule.dart';
import '../../util/week_set.dart';

/// 打开周次选择对话框，返回用户确定的 [WeekRule]（取消返回 null）。
///
/// 两种模式共存、可随时切换且保留各自状态：
/// - 「逐周选择」：在 1..N 网格里逐个勾选，适合无规律的散列周次。
/// - 「范围轮换」：设起止周 + 每 X 周轮换 + 周期内第几周上课，适合规律排课
///   （连续、单双周、每 3 周中的第 1、2 周等）。
Future<WeekRule?> showWeekRulePicker(
  BuildContext context, {
  required WeekRule initial,
  Calendar? calendar,
}) {
  final calWeeks = calendar?.weekCount ?? Calendar.defaultWeekCount;
  return showDialog<WeekRule>(
    context: context,
    builder: (_) => _WeekRulePicker(initial: initial, calWeeks: calWeeks),
  );
}

class _WeekRulePicker extends StatefulWidget {
  final WeekRule initial;
  final int calWeeks;

  const _WeekRulePicker({required this.initial, required this.calWeeks});

  @override
  State<_WeekRulePicker> createState() => _WeekRulePickerState();
}

class _WeekRulePickerState extends State<_WeekRulePicker> {
  /// 网格「增加周数」每次放大的格数，以及网格能扩到的上界（防误触无限拉长）。
  static const int _weekGridStep = 5;
  static const int _maxWeekGrid = 60;

  /// true=逐周选择；false=范围轮换。真轮换（interval>1）与「第 N 周起、无上
  /// 界」的规则网格表达不了（会被截断成有界），默认落范围模式；其余（显式列
  /// 表、连续范围、每周）默认逐周网格。
  late bool _perWeek = _defaultsToPerWeek(widget.initial);

  /// 最近一次编辑发生在哪个模式（null=尚未编辑）。切换模式时把该侧的选择
  /// 换算过去，让两种模式操作同一份「当前选择」而不是各自为政。
  bool? _dirtyPerWeek;

  static bool _defaultsToPerWeek(WeekRule r) {
    if (r.include.isNotEmpty) return true;
    if (rotationPhases(r).isNotEmpty) return false;
    if (r.toWeek <= 0 && r.fromWeek > 1) return false;
    return true;
  }

  // —— 逐周模式状态 ——
  late int _gridCount = weekGridCount(widget.initial, defaultWeeks: widget.calWeeks);
  late Set<int> _selected = weeksOfRule(widget.initial, _gridCount);

  // —— 范围轮换模式状态 ——
  late int _from = widget.initial.fromWeek >= 1 ? widget.initial.fromWeek : 1;
  late bool _bounded = widget.initial.toWeek > 0;
  late int _to = widget.initial.toWeek > 0
      ? widget.initial.toWeek
      : (widget.initial.fromWeek >= 1 ? widget.initial.fromWeek : 1) +
          widget.calWeeks -
          1;
  late int _interval = widget.initial.interval >= 1 ? widget.initial.interval : 1;

  /// 周期内生效的「第几周」（1-based，相对轮换起点，即范围起始周所在周期）。
  late Set<int> _activeOrdinals = _initialOrdinals();

  Set<int> _initialOrdinals() {
    final r = widget.initial;
    final total = r.interval >= 1 ? r.interval : 1;
    if (total <= 1) return {1};
    final from = r.fromWeek >= 1 ? r.fromWeek : 1;
    return {
      for (final o in r.offsets) ((o - (from - 1)) % total + total) % total + 1,
    };
  }

  /// 切换模式：若另一侧有更新的编辑，先把它换算成本侧状态（网格 ↔ 规则），
  /// 保证切换后看到的是同一份选择。无上界规则展开到网格会按格数截断——只有
  /// 在逐周模式里确定才会真的定型为有界。
  void _switchMode(bool perWeek) {
    if (perWeek == _perWeek) return;
    setState(() {
      if (perWeek && _dirtyPerWeek == false) {
        final rule = _buildRange();
        _gridCount = weekGridCount(
          rule,
          defaultWeeks: math.max(widget.calWeeks, _gridCount),
        );
        _selected = weeksOfRule(rule, _gridCount);
      } else if (!perWeek && _dirtyPerWeek == true) {
        _seedRangeFrom(weekRuleFromWeeks(_selected));
      }
      _dirtyPerWeek = null;
      _perWeek = perWeek;
    });
  }

  /// 用 [r] 重置范围模式状态。无规律的显式列表规约不出轮换，退化为覆盖
  /// [WeekRule.fromWeek]..[WeekRule.toWeek] 的连续范围（预览会如实显示）。
  void _seedRangeFrom(WeekRule r) {
    _from = r.fromWeek >= 1 ? r.fromWeek : 1;
    _bounded = r.toWeek > 0;
    if (_bounded) _to = r.toWeek;
    final phases = rotationPhases(r);
    if (r.include.isNotEmpty || phases.isEmpty) {
      _interval = 1;
      _activeOrdinals = {1};
    } else {
      _interval = r.interval;
      _activeOrdinals = {
        for (final p in phases)
          ((p - (_from - 1)) % r.interval + r.interval) % r.interval + 1,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择周次'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('范围轮换')),
                  ButtonSegment(value: true, label: Text('逐周选择')),
                ],
                selected: {_perWeek},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _switchMode(s.first),
              ),
              const SizedBox(height: 16),
              if (_perWeek) _perWeekBody() else _rangeBody(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _canConfirm ? () => Navigator.pop(context, _build()) : null,
          child: const Text('确定'),
        ),
      ],
    );
  }

  // —— 逐周模式 ——

  /// 逐周/范围模式内的编辑：记下最近编辑侧，供切换模式时换算。
  void _editGrid(VoidCallback fn) =>
      setState(() {
        fn();
        _dirtyPerWeek = true;
      });

  void _editRange(VoidCallback fn) =>
      setState(() {
        fn();
        _dirtyPerWeek = false;
      });

  Widget _perWeekBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (final (label, weeks) in [
              ('全选', {for (var w = 1; w <= _gridCount; w++) w}),
              ('单周', {for (var w = 1; w <= _gridCount; w += 2) w}),
              ('双周', {for (var w = 2; w <= _gridCount; w += 2) w}),
              ('清空', <int>{}),
            ])
              ActionChip(
                label: Text(label),
                visualDensity: VisualDensity.compact,
                onPressed: () => _editGrid(() => _selected = {...weeks}),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var w = 1; w <= _gridCount; w++)
              FilterChip(
                label: Text('$w'),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                selected: _selected.contains(w),
                onSelected: (on) => _editGrid(() {
                  if (on) {
                    _selected.add(w);
                  } else {
                    _selected.remove(w);
                  }
                }),
              ),
            if (_gridCount < _maxWeekGrid)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('增加周数'),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(
                  () => _gridCount =
                      (_gridCount + _weekGridStep).clamp(0, _maxWeekGrid),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // —— 范围轮换模式 ——

  Widget _rangeBody() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepperRow(
          label: '起始周',
          value: _from,
          onChanged: (v) => _editRange(() {
            _from = v.clamp(1, 999);
            if (_bounded && _to < _from) _to = _from;
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: _bounded,
              onChanged: (v) => _editRange(() {
                _bounded = v ?? false;
                if (_bounded && _to < _from) _to = _from + widget.calWeeks - 1;
              }),
            ),
            const Text('设置结束周'),
          ],
        ),
        if (_bounded)
          _stepperRow(
            label: '结束周',
            value: _to,
            onChanged: (v) => _editRange(() => _to = v.clamp(_from, 999)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text('不限结束周（随学期延伸）',
                style: TextStyle(color: scheme.outline, fontSize: 12)),
          ),
        const Divider(height: 24),
        _stepperRow(
          label: '每 N 周轮换',
          value: _interval,
          min: 1,
          onChanged: (v) => _editRange(() {
            _interval = v.clamp(1, 12);
            _activeOrdinals =
                _activeOrdinals.where((o) => o <= _interval).toSet();
            if (_activeOrdinals.isEmpty) _activeOrdinals = {1};
          }),
        ),
        if (_interval > 1) ...[
          const SizedBox(height: 12),
          Text('周期内上课的周',
              style: TextStyle(color: scheme.primary, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var n = 1; n <= _interval; n++)
                FilterChip(
                  label: Text('第 $n 周'),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selected: _activeOrdinals.contains(n),
                  onSelected: (on) => _editRange(() {
                    if (on) {
                      _activeOrdinals.add(n);
                    } else if (_activeOrdinals.length > 1) {
                      _activeOrdinals.remove(n);
                    }
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Builder(builder: (context) {
          final rule = _buildRange();
          final int horizon = rule.toWeek > 0
              ? rule.toWeek
              : math.max(
                  widget.calWeeks,
                  rule.fromWeek + 3 * math.max(1, rule.interval),
                );
          final hits = weeksOfRule(rule, horizon).toList()..sort();
          final hitText = hits.isEmpty
              ? '当前设置不命中任何周次'
              : '命中：第 ${hits.join('、')} 周${rule.toWeek > 0 ? '' : '…'}';
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_repeat, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        weekRuleLabel(rule),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hitText,
                  style: TextStyle(
                    fontSize: 12,
                    color: hits.isEmpty ? scheme.error : scheme.outline,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _stepperRow({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    int min = 1,
  }) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          visualDensity: VisualDensity.compact,
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 32,
          child: Text('$value', textAlign: TextAlign.center),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }

  bool get _canConfirm {
    if (_perWeek) return _selected.isNotEmpty;
    final rule = _buildRange();
    // 无上界规则必然命中未来某周；有界规则可能与轮换相位错开而一周不中。
    return rule.toWeek <= 0 || weeksOfRule(rule, rule.toWeek).isNotEmpty;
  }

  WeekRule _buildRange() {
    final total = _interval < 1 ? 1 : _interval;
    // 周期内全选与不轮换等价，直接落「每周 + 范围」。
    if (total <= 1 || _activeOrdinals.length >= total) {
      return WeekRule(fromWeek: _from, toWeek: _bounded ? _to : 0);
    }
    // 周期内序数（相对范围起点）→ 学期周绝对相位。
    final offsets = {
      for (final n in _activeOrdinals) (_from - 1 + n - 1) % total,
    }.toList()
      ..sort();
    return WeekRule(
      interval: total,
      offsets: offsets,
      fromWeek: _from,
      toWeek: _bounded ? _to : 0,
    );
  }

  WeekRule _build() => _perWeek ? weekRuleFromWeeks(_selected) : _buildRange();
}
