import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models/bell_schedule.dart';
import '../../models/calendar.dart';
import '../../util/coerce.dart';
import '../../util/format.dart';

/// 一节课的时间取值：按节次（[custom] 为假，用 [startPeriod]/[endPeriod]）或
/// 自定义时刻（[custom] 为真，用 [customStart]/[customEnd]）。
class LessonTimeValue {
  final bool custom;
  final int startPeriod;
  final int endPeriod;
  final TimeOfDay? customStart;
  final TimeOfDay? customEnd;

  const LessonTimeValue({
    required this.custom,
    this.startPeriod = 1,
    this.endPeriod = 1,
    this.customStart,
    this.customEnd,
  });

  LessonTimeValue copyWith({
    bool? custom,
    int? startPeriod,
    int? endPeriod,
    TimeOfDay? customStart,
    TimeOfDay? customEnd,
  }) =>
      LessonTimeValue(
        custom: custom ?? this.custom,
        startPeriod: startPeriod ?? this.startPeriod,
        endPeriod: endPeriod ?? this.endPeriod,
        customStart: customStart ?? this.customStart,
        customEnd: customEnd ?? this.customEnd,
      );

  /// 自定义时刻是否已选齐且结束晚于开始。
  bool get customTimeValid {
    final s = customStart;
    final e = customEnd;
    if (s == null || e == null) return false;
    return e.hour * 60 + e.minute > s.hour * 60 + s.minute;
  }
}

/// `HH:mm` 字符串 → [TimeOfDay]（解析失败返回 null）。
TimeOfDay? timeOfDayFromHhmm(String? hhmm) {
  final d = parseHhmm(hhmm);
  if (d == null) return null;
  return TimeOfDay(hour: d.inHours % 24, minute: d.inMinutes.remainder(60));
}

/// [TimeOfDay] → `HH:mm`。
String hhmmFromTimeOfDay(TimeOfDay t) =>
    durationToHhmm(Duration(hours: t.hour, minutes: t.minute));

/// 受控的「按节次 / 自定义时刻」时间选择块：分段切换 + 开始/结束节下拉（候选来
/// 自作息表，兜底 1..N，始终含当前值）+「对应 HH:mm（跟随作息表）」预览，或
/// 自定义时刻的两个时间按钮。星期与作息表由外部传入，仅用于解析节次时刻预览。
class LessonTimeFields extends StatelessWidget {
  final Calendar? calendar;
  final int weekday;
  final String? bellScheduleId;
  final LessonTimeValue value;
  final ValueChanged<LessonTimeValue> onChanged;

  const LessonTimeFields({
    super.key,
    required this.calendar,
    required this.weekday,
    required this.bellScheduleId,
    required this.value,
    required this.onChanged,
  });

  /// 求解节次时刻用的作息表：Meeting 覆盖 → 星期指派/默认 → 数据库还没有作息
  /// 时用保存后会自动创建的 [AppState.defaultBellSchedule]。
  BellSchedule? get _bell {
    final cal = calendar;
    final id = bellScheduleId;
    if (id != null && cal?.bellSchedules[id] != null) {
      return cal!.bellSchedules[id];
    }
    final byDay = cal?.bellScheduleForWeekday(weekday);
    if (byDay != null) return byDay;
    if (cal == null || cal.bellSchedules.isEmpty) {
      return AppState.defaultBellSchedule;
    }
    return null;
  }

  /// 节次下拉候选：作息表里实际存在的上课节次；无作息则 1..N 兜底。始终包含
  /// 当前值，避免下拉框 value 不在 items 里。
  List<int> get _periodChoices {
    final fromBell = _bell?.classByIndex.keys.toList() ?? const <int>[];
    final base = fromBell.isNotEmpty
        ? fromBell
        : [
            for (var i = 1;
                i <= ((calendar?.maxClassPeriod ?? 0) > 0
                    ? calendar!.maxClassPeriod
                    : 8);
                i++)
              i
          ];
    return <int>{...base, value.startPeriod, value.endPeriod}
        .where((p) => p >= 1)
        .toList()
      ..sort();
  }

  String? get _periodTimePreview {
    final byIndex = _bell?.classByIndex;
    if (byIndex == null) return null;
    final s = byIndex[value.startPeriod];
    if (s == null) return null;
    final e = byIndex[value.endPeriod] ?? s;
    return '${hm(s.start)} - ${hm(e.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.format_list_numbered),
              label: Text('按节次'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.schedule_outlined),
              label: Text('自定义时刻'),
            ),
          ],
          selected: {value.custom},
          onSelectionChanged: (s) =>
              onChanged(value.copyWith(custom: s.first)),
        ),
        const SizedBox(height: 12),
        if (!value.custom) ...[
          Row(
            children: [
              Expanded(child: _periodDropdown(isStart: true)),
              const SizedBox(width: 12),
              Expanded(child: _periodDropdown(isStart: false)),
            ],
          ),
          if (_periodTimePreview != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '对应 $_periodTimePreview（跟随作息表）',
                style: textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ),
        ] else
          Row(
            children: [
              Expanded(child: _timeButton(context, isStart: true)),
              const SizedBox(width: 12),
              Expanded(child: _timeButton(context, isStart: false)),
            ],
          ),
      ],
    );
  }

  Widget _periodDropdown({required bool isStart}) {
    final current = isStart ? value.startPeriod : value.endPeriod;
    final choices = isStart
        ? _periodChoices
        : _periodChoices.where((p) => p >= value.startPeriod).toList();
    return InputDecorator(
      decoration: InputDecoration(
        labelText: isStart ? '开始节' : '结束节',
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButton<int>(
        value: current,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [
          for (final p in choices)
            DropdownMenuItem(value: p, child: Text('第 $p 节')),
        ],
        onChanged: (v) {
          if (v == null) return;
          if (isStart) {
            onChanged(value.copyWith(
              startPeriod: v,
              endPeriod: value.endPeriod < v ? v : value.endPeriod,
            ));
          } else {
            onChanged(value.copyWith(endPeriod: v));
          }
        },
      ),
    );
  }

  Widget _timeButton(BuildContext context, {required bool isStart}) {
    final t = isStart ? value.customStart : value.customEnd;
    return OutlinedButton.icon(
      icon: const Icon(Icons.schedule_outlined, size: 18),
      label: Text(
        t == null
            ? (isStart ? '开始时间' : '结束时间')
            : '${isStart ? '开始' : '结束'} ${hhmmFromTimeOfDay(t)}',
      ),
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: t ??
              (isStart
                  ? const TimeOfDay(hour: 19, minute: 0)
                  : const TimeOfDay(hour: 20, minute: 0)),
        );
        if (picked == null) return;
        onChanged(isStart
            ? value.copyWith(customStart: picked)
            : value.copyWith(customEnd: picked));
      },
    );
  }
}
