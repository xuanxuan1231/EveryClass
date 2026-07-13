import '../util/coerce.dart';

/// 提醒（对齐 JSCalendar `Alert` + `OffsetTrigger`）。
///
/// 相对课程 [relativeToEnd] ? 结束 : 开始，偏移 [offset]（负=之前）。
class Alert {
  final Duration offset;
  final bool relativeToEnd;

  const Alert({required this.offset, this.relativeToEnd = false});

  /// 上课前 [d] 提醒。
  factory Alert.beforeStart(Duration d) => Alert(offset: -d);

  factory Alert.fromJson(Map<String, dynamic> json) {
    final trigger = asMap(pick(json, ['trigger', 'Trigger']));
    final rel = asString(
      pick(trigger, ['relativeTo', 'RelativeTo']) ??
          pick(json, ['relativeTo']),
    ).toLowerCase();
    final raw = pick(trigger, ['offset', 'Offset']) ?? pick(json, ['offset']);
    return Alert(
      offset: parseIso8601Duration(raw) ?? Duration.zero,
      relativeToEnd: rel == 'end',
    );
  }

  Map<String, dynamic> toJson() => {
        '@type': 'Alert',
        'trigger': {
          '@type': 'OffsetTrigger',
          'relativeTo': relativeToEnd ? 'end' : 'start',
          'offset': iso8601Duration(offset),
        },
        'action': 'display',
      };
}
