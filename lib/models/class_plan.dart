import '../util/coerce.dart';

/// 课表启用规则（对齐 ClassIsland `TimeRule`）。
class TimeRule {
  /// 星期，1–7（周一=1）。
  final int weekDay;

  /// 轮换周序号：0 = 每周生效；n = 在 [weekCountDivTotal] 周循环中的第 n 周生效。
  final int weekCountDiv;

  /// 轮换周期长度（默认 2，即单/双周）。
  final int weekCountDivTotal;

  const TimeRule({
    this.weekDay = 0,
    this.weekCountDiv = 0,
    this.weekCountDivTotal = 2,
  });

  factory TimeRule.fromJson(Map<String, dynamic> json) {
    return TimeRule(
      weekDay: asInt(pick(json, ['WeekDay', 'weekDay'])),
      weekCountDiv: asInt(pick(json, ['WeekCountDiv', 'weekCountDiv'])),
      weekCountDivTotal: asInt(
        pick(json, ['WeekCountDivTotal', 'weekCountDivTotal']),
        fallback: 2,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'WeekDay': weekDay,
      'WeekCountDiv': weekCountDiv,
      'WeekCountDivTotal': weekCountDivTotal,
    };
  }
}

/// 一节课的排布（对齐 ClassIsland `ClassInfo`）。
///
/// 走班扩展：新增 [room]，可覆盖对应 `Subject.defaultRoom`。
class ClassInfo {
  /// `AttachedObjects` 中存放走班教室的键名。
  static const String roomKey = 'everyclass.room';

  final String subjectId;
  final bool isEnabled;
  final bool isChangedClass;

  /// 走班扩展：该节课的教室（覆盖科目默认教室）。
  final String room;

  final Map<String, dynamic> attachedObjects;

  const ClassInfo({
    required this.subjectId,
    this.isEnabled = true,
    this.isChangedClass = false,
    this.room = '',
    this.attachedObjects = const {},
  });

  ClassInfo copyWith({String? subjectId, String? room}) {
    return ClassInfo(
      subjectId: subjectId ?? this.subjectId,
      isEnabled: isEnabled,
      isChangedClass: isChangedClass,
      room: room ?? this.room,
      attachedObjects: attachedObjects,
    );
  }

  factory ClassInfo.fromJson(Map<String, dynamic> json) {
    final attached = asMap(pick(json, ['AttachedObjects', 'attachedObjects']));
    return ClassInfo(
      subjectId: asString(pick(json, ['SubjectId', 'subjectId'])),
      isEnabled: asBool(pick(json, ['IsEnabled', 'isEnabled']), fallback: true),
      isChangedClass: asBool(pick(json, ['IsChangedClass', 'isChangedClass'])),
      room: asString(pick(json, ['Room', 'room']) ?? attached[roomKey]),
      attachedObjects: attached,
    );
  }

  Map<String, dynamic> toJson() {
    final attached = Map<String, dynamic>.from(attachedObjects);
    if (room.isNotEmpty) {
      attached[roomKey] = room;
    } else {
      attached.remove(roomKey);
    }
    return {
      'SubjectId': subjectId,
      'IsEnabled': isEnabled,
      'IsChangedClass': isChangedClass,
      'AttachedObjects': attached,
    };
  }
}

/// 一张课表（对齐 ClassIsland `ClassPlan`）。
class ClassPlan {
  final String name;
  final String timeLayoutId;
  final TimeRule timeRule;
  final List<ClassInfo> classes;
  final bool isEnabled;
  final bool isOverlay;
  final String associatedGroup;

  const ClassPlan({
    this.name = '',
    required this.timeLayoutId,
    this.timeRule = const TimeRule(),
    this.classes = const [],
    this.isEnabled = true,
    this.isOverlay = false,
    this.associatedGroup = '',
  });

  factory ClassPlan.fromJson(Map<String, dynamic> json) {
    return ClassPlan(
      name: asString(pick(json, ['Name', 'name'])),
      timeLayoutId: asString(pick(json, ['TimeLayoutId', 'timeLayoutId'])),
      timeRule: TimeRule.fromJson(asMap(pick(json, ['TimeRule', 'timeRule']))),
      classes: asList(pick(json, ['Classes', 'classes']))
          .whereType<Map>()
          .map((e) => ClassInfo.fromJson(e.cast<String, dynamic>()))
          .toList(),
      isEnabled: asBool(pick(json, ['IsEnabled', 'isEnabled']), fallback: true),
      isOverlay: asBool(pick(json, ['IsOverlay', 'isOverlay'])),
      associatedGroup: asString(pick(json, ['AssociatedGroup', 'associatedGroup'])),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Name': name,
      'TimeLayoutId': timeLayoutId,
      'TimeRule': timeRule.toJson(),
      'Classes': classes.map((e) => e.toJson()).toList(),
      'IsEnabled': isEnabled,
      'IsOverlay': isOverlay,
      'AssociatedGroup': associatedGroup,
    };
  }
}
