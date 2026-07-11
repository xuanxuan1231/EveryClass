import '../util/coerce.dart';

/// 科目（对齐 ClassIsland 的 `Subject`）。
///
/// 走班扩展：新增 [defaultRoom]（ClassIsland 没有教室概念）。为保持导出档案仍是
/// 合法的 ClassIsland 档案，教室会镜像写入 `AttachedObjects` 的 [roomKey] 键。
class Subject {
  /// `AttachedObjects` 中存放走班教室的键名。
  static const String roomKey = 'everyclass.room';

  final String name;
  final String initial;
  final String teacherName;
  final bool isOutDoor;

  /// 走班扩展：该科目的默认教室。
  final String defaultRoom;

  /// ClassIsland 的 `AttachedObjects`，原样保留以便往返兼容。
  final Map<String, dynamic> attachedObjects;

  const Subject({
    required this.name,
    this.initial = '',
    this.teacherName = '',
    this.isOutDoor = false,
    this.defaultRoom = '',
    this.attachedObjects = const {},
  });

  Subject copyWith({
    String? name,
    String? initial,
    String? teacherName,
    bool? isOutDoor,
    String? defaultRoom,
    Map<String, dynamic>? attachedObjects,
  }) {
    return Subject(
      name: name ?? this.name,
      initial: initial ?? this.initial,
      teacherName: teacherName ?? this.teacherName,
      isOutDoor: isOutDoor ?? this.isOutDoor,
      defaultRoom: defaultRoom ?? this.defaultRoom,
      attachedObjects: attachedObjects ?? this.attachedObjects,
    );
  }

  factory Subject.fromJson(Map<String, dynamic> json) {
    final attached = asMap(pick(json, ['AttachedObjects', 'attachedObjects']));
    final room = asString(
      pick(json, ['DefaultRoom', 'defaultRoom']) ?? attached[roomKey],
    );
    return Subject(
      name: asString(pick(json, ['Name', 'name'])),
      initial: asString(pick(json, ['Initial', 'initial'])),
      teacherName: asString(pick(json, ['TeacherName', 'teacherName'])),
      isOutDoor: asBool(pick(json, ['IsOutDoor', 'isOutDoor'])),
      defaultRoom: room,
      attachedObjects: attached,
    );
  }

  Map<String, dynamic> toJson() {
    final attached = Map<String, dynamic>.from(attachedObjects);
    if (defaultRoom.isNotEmpty) {
      attached[roomKey] = defaultRoom;
    } else {
      attached.remove(roomKey);
    }
    return {
      'Name': name,
      'Initial': initial,
      'TeacherName': teacherName,
      'IsOutDoor': isOutDoor,
      'AttachedObjects': attached,
    };
  }
}
