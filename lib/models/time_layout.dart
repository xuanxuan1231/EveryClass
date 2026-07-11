import '../util/coerce.dart';

/// 时间点类型（对齐 ClassIsland `TimeType`）。
enum TimeType {
  lesson, // 0 上课
  breakTime, // 1 课间
  action; // 2 行动/其他

  static TimeType fromRaw(int raw) {
    switch (raw) {
      case 0:
        return TimeType.lesson;
      case 1:
        return TimeType.breakTime;
      default:
        return TimeType.action;
    }
  }
}

/// 时间表中的单个时间点（对齐 ClassIsland `TimeLayoutItem`）。
class TimeLayoutItem {
  /// 距零点的开始时刻。
  final Duration start;

  /// 距零点的结束时刻。
  final Duration end;

  final TimeType timeType;

  /// 原始 TimeType 整数（可能超出已知枚举，回写时保留）。
  final int rawTimeType;

  final String breakName;
  final String defaultClassId;
  final Map<String, dynamic> attachedObjects;

  const TimeLayoutItem({
    required this.start,
    required this.end,
    required this.timeType,
    required this.rawTimeType,
    this.breakName = '',
    this.defaultClassId = '',
    this.attachedObjects = const {},
  });

  bool get isLesson => timeType == TimeType.lesson;

  factory TimeLayoutItem.fromJson(Map<String, dynamic> json) {
    final raw = asInt(pick(json, ['TimeType', 'timeType']));
    return TimeLayoutItem(
      start:
          parseTimeOfDay(pick(json, ['StartTime', 'StartSecond', 'start'])) ??
          Duration.zero,
      end:
          parseTimeOfDay(pick(json, ['EndTime', 'EndSecond', 'end'])) ??
          Duration.zero,
      timeType: TimeType.fromRaw(raw),
      rawTimeType: raw,
      breakName: asString(pick(json, ['BreakName', 'breakName'])),
      defaultClassId: asString(pick(json, ['DefaultClassId', 'defaultClassId'])),
      attachedObjects: asMap(pick(json, ['AttachedObjects', 'attachedObjects'])),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'StartTime': durationToTimeSpan(start),
      'EndTime': durationToTimeSpan(end),
      'TimeType': rawTimeType,
      if (breakName.isNotEmpty) 'BreakName': breakName,
      if (defaultClassId.isNotEmpty) 'DefaultClassId': defaultClassId,
      'AttachedObjects': attachedObjects,
    };
  }
}

/// 时间表（对齐 ClassIsland `TimeLayout`）。
class TimeLayout {
  final String name;
  final List<TimeLayoutItem> items;

  const TimeLayout({required this.name, this.items = const []});

  /// 仅上课类型的时间点，按时间顺序——`ClassPlan.classes` 与之一一对应。
  List<TimeLayoutItem> get lessonItems =>
      items.where((e) => e.isLesson).toList();

  factory TimeLayout.fromJson(Map<String, dynamic> json) {
    return TimeLayout(
      name: asString(pick(json, ['Name', 'name'])),
      items: asList(pick(json, ['Layouts', 'layouts', 'items']))
          .whereType<Map>()
          .map((e) => TimeLayoutItem.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'Name': name, 'Layouts': items.map((e) => e.toJson()).toList()};
  }
}
