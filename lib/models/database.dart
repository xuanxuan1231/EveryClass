import '../util/coerce.dart';
import 'calendar.dart';

/// 顶层容器：持有多张学期课表 [calendars]，当前选中 [selectedCalendarId]。
class Database {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String selectedCalendarId;
  final Map<String, Calendar> calendars;
  final Map<String, dynamic> extra;

  const Database({
    this.schemaVersion = currentSchemaVersion,
    this.selectedCalendarId = '',
    this.calendars = const {},
    this.extra = const {},
  });

  factory Database.empty() => const Database();

  /// 当前选中的课表：选中 ID 命中 → 命中；否则取第一张；都没有则 null。
  Calendar? get selected {
    final sel = calendars[selectedCalendarId];
    if (sel != null) return sel;
    return calendars.isNotEmpty ? calendars.values.first : null;
  }

  bool get isEmpty => calendars.isEmpty;

  Database copyWith({
    String? selectedCalendarId,
    Map<String, Calendar>? calendars,
  }) {
    return Database(
      schemaVersion: schemaVersion,
      selectedCalendarId: selectedCalendarId ?? this.selectedCalendarId,
      calendars: calendars ?? this.calendars,
      extra: extra,
    );
  }

  /// 替换（或新增）一张课表并返回新 Database。
  Database withCalendar(Calendar calendar) {
    final next = Map<String, Calendar>.from(calendars);
    next[calendar.id] = calendar;
    return copyWith(
      calendars: next,
      selectedCalendarId:
          selectedCalendarId.isEmpty ? calendar.id : selectedCalendarId,
    );
  }

  /// 删除一张课表；若删的是选中项（或选中 ID 已失效），改选剩余的第一张，
  /// 没有剩余则清空选中。未命中时原样返回。
  Database withoutCalendar(String id) {
    if (!calendars.containsKey(id)) return this;
    final next = Map<String, Calendar>.from(calendars)..remove(id);
    var sel = selectedCalendarId;
    if (!next.containsKey(sel)) {
      sel = next.isEmpty ? '' : next.keys.first;
    }
    return copyWith(calendars: next, selectedCalendarId: sel);
  }

  factory Database.fromJson(Map<String, dynamic> json) {
    return Database(
      schemaVersion: asInt(
        pick(json, ['schemaVersion', 'SchemaVersion']),
        fallback: currentSchemaVersion,
      ),
      selectedCalendarId: asString(
        pick(json, ['selectedCalendarId', 'SelectedCalendarId']),
      ),
      calendars: asMap(pick(json, ['calendars', 'Calendars'])).map(
        (k, v) => MapEntry(k, Calendar.fromJson(asMap(v), id: k)),
      ),
      extra: asMap(pick(json, ['extra', 'Extra'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'selectedCalendarId': selectedCalendarId,
        'calendars': calendars.map((k, v) => MapEntry(k, v.toJson())),
        if (extra.isNotEmpty) 'extra': extra,
      };
}
