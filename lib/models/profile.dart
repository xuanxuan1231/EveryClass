import '../util/coerce.dart';
import 'class_plan.dart';
import 'subject.dart';
import 'time_layout.dart';

/// 课表群组（对齐 ClassIsland `ClassPlanGroup`）。
class ClassPlanGroup {
  final String name;
  final bool isGlobal;

  const ClassPlanGroup({this.name = '', this.isGlobal = false});

  factory ClassPlanGroup.fromJson(Map<String, dynamic> json) {
    return ClassPlanGroup(
      name: asString(pick(json, ['Name', 'name'])),
      isGlobal: asBool(pick(json, ['IsGlobal', 'isGlobal'])),
    );
  }

  Map<String, dynamic> toJson() => {'Name': name, 'IsGlobal': isGlobal};
}

/// 档案根对象（对齐 ClassIsland `Profile`）。
///
/// v1 只解析并参与计算核心的三张字典（Subjects / TimeLayouts / ClassPlans）与
/// 群组信息；overlay / temp / orderedSchedules 等高级层通过 [extra] 原样保留，
/// 以便日后扩展且导出时不丢字段。
class Profile {
  /// 顶层已被识别的键——其余键落入 [extra] 原样保留。
  static const Set<String> _knownKeys = {
    'Name',
    'Id',
    'Subjects',
    'TimeLayouts',
    'ClassPlans',
    'ClassPlanGroups',
    'SelectedClassPlanGroupId',
  };

  final String name;
  final String id;
  final Map<String, Subject> subjects;
  final Map<String, TimeLayout> timeLayouts;
  final Map<String, ClassPlan> classPlans;
  final Map<String, ClassPlanGroup> classPlanGroups;
  final String selectedClassPlanGroupId;

  /// 未识别的顶层字段，原样保留以便往返兼容。
  final Map<String, dynamic> extra;

  const Profile({
    this.name = '',
    this.id = '',
    this.subjects = const {},
    this.timeLayouts = const {},
    this.classPlans = const {},
    this.classPlanGroups = const {},
    this.selectedClassPlanGroupId = '',
    this.extra = const {},
  });

  factory Profile.empty() => const Profile();

  Profile copyWith({
    Map<String, Subject>? subjects,
    Map<String, TimeLayout>? timeLayouts,
    Map<String, ClassPlan>? classPlans,
  }) {
    return Profile(
      name: name,
      id: id,
      subjects: subjects ?? this.subjects,
      timeLayouts: timeLayouts ?? this.timeLayouts,
      classPlans: classPlans ?? this.classPlans,
      classPlanGroups: classPlanGroups,
      selectedClassPlanGroupId: selectedClassPlanGroupId,
      extra: extra,
    );
  }

  static Map<String, T> _mapOf<T>(
    dynamic v,
    T Function(Map<String, dynamic>) from,
  ) {
    return asMap(v).map((k, val) => MapEntry(k, from(asMap(val))));
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key)) extra[entry.key] = entry.value;
    }
    return Profile(
      name: asString(pick(json, ['Name', 'name'])),
      id: asString(pick(json, ['Id', 'id'])),
      subjects: _mapOf(
        pick(json, ['Subjects', 'subjects']),
        Subject.fromJson,
      ),
      timeLayouts: _mapOf(
        pick(json, ['TimeLayouts', 'timeLayouts']),
        TimeLayout.fromJson,
      ),
      classPlans: _mapOf(
        pick(json, ['ClassPlans', 'classPlans']),
        ClassPlan.fromJson,
      ),
      classPlanGroups: _mapOf(
        pick(json, ['ClassPlanGroups', 'classPlanGroups']),
        ClassPlanGroup.fromJson,
      ),
      selectedClassPlanGroupId: asString(
        pick(json, ['SelectedClassPlanGroupId', 'selectedClassPlanGroupId']),
      ),
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Name': name,
      'Id': id,
      'Subjects': subjects.map((k, v) => MapEntry(k, v.toJson())),
      'TimeLayouts': timeLayouts.map((k, v) => MapEntry(k, v.toJson())),
      'ClassPlans': classPlans.map((k, v) => MapEntry(k, v.toJson())),
      'ClassPlanGroups':
          classPlanGroups.map((k, v) => MapEntry(k, v.toJson())),
      'SelectedClassPlanGroupId': selectedClassPlanGroupId,
      ...extra,
    };
  }
}
