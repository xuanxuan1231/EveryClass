import '../util/coerce.dart';
import 'alert.dart';
import 'meeting.dart';

/// 课程：一门课的语义聚合（名称、颜色、图标、教师、标签、备注、默认地点、
/// 默认提醒）+ 若干周期性排课 [meetings]。≈ 一组共享元数据的 JSCalendar Event。
class CourseEvent {
  final String id;
  final String title;

  /// 课程颜色（`#RRGGBB`）与图标名（扩展）。
  final String color;
  final String icon;

  /// 任课教师（便捷字符串）。
  final String teacher;

  /// 一学期基本不变的默认地点（走班）。
  final String defaultLocation;

  /// 标签（对齐 JSCalendar `keywords`）。
  final List<String> keywords;

  /// 备注（对齐 JSCalendar `description`）。
  final String description;

  /// 课程级默认提醒。
  final List<Alert> alerts;

  final List<Meeting> meetings;

  final Map<String, dynamic> extra;

  const CourseEvent({
    required this.id,
    this.title = '',
    this.color = '',
    this.icon = '',
    this.teacher = '',
    this.defaultLocation = '',
    this.keywords = const [],
    this.description = '',
    this.alerts = const [],
    this.meetings = const [],
    this.extra = const {},
  });

  CourseEvent copyWith({
    String? title,
    String? color,
    String? icon,
    String? teacher,
    String? defaultLocation,
    List<String>? keywords,
    String? description,
    List<Alert>? alerts,
    List<Meeting>? meetings,
  }) {
    return CourseEvent(
      id: id,
      title: title ?? this.title,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      teacher: teacher ?? this.teacher,
      defaultLocation: defaultLocation ?? this.defaultLocation,
      keywords: keywords ?? this.keywords,
      description: description ?? this.description,
      alerts: alerts ?? this.alerts,
      meetings: meetings ?? this.meetings,
      extra: extra,
    );
  }

  factory CourseEvent.fromJson(Map<String, dynamic> json, {String? id}) {
    return CourseEvent(
      id: asString(pick(json, ['id', 'Id']) ?? id),
      title: asString(pick(json, ['title', 'Title', 'name', 'Name'])),
      color: asString(pick(json, ['color', 'Color'])),
      icon: asString(pick(json, ['icon', 'Icon'])),
      teacher: asString(pick(json, ['teacher', 'Teacher', 'TeacherName'])),
      defaultLocation: asString(
        pick(json, ['defaultLocation', 'DefaultLocation']),
      ),
      keywords: asList(pick(json, ['keywords', 'Keywords']))
          .map((e) => asString(e))
          .where((e) => e.isNotEmpty)
          .toList(),
      description: asString(pick(json, ['description', 'Description'])),
      alerts: asList(pick(json, ['alerts', 'Alerts']))
          .whereType<Map>()
          .map((e) => Alert.fromJson(e.cast<String, dynamic>()))
          .toList(),
      meetings: asList(pick(json, ['meetings', 'Meetings']))
          .whereType<Map>()
          .map((e) => Meeting.fromJson(e.cast<String, dynamic>()))
          .toList(),
      extra: asMap(pick(json, ['extra', 'Extra'])),
    );
  }

  Map<String, dynamic> toJson() => {
        '@type': 'CourseEvent',
        'id': id,
        'title': title,
        if (color.isNotEmpty) 'color': color,
        if (icon.isNotEmpty) 'icon': icon,
        if (teacher.isNotEmpty) 'teacher': teacher,
        if (defaultLocation.isNotEmpty) 'defaultLocation': defaultLocation,
        if (keywords.isNotEmpty) 'keywords': keywords,
        if (description.isNotEmpty) 'description': description,
        if (alerts.isNotEmpty)
          'alerts': alerts.map((e) => e.toJson()).toList(),
        'meetings': meetings.map((e) => e.toJson()).toList(),
        if (extra.isNotEmpty) 'extra': extra,
      };
}
