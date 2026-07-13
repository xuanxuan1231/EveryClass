import '../util/coerce.dart';

/// 节次类型。只有 [BellPeriodKind.klass] 参与节次编号并可被课程引用。
enum BellPeriodKind {
  klass, // 上课
  breakTime, // 课间
  lunch, // 午休
  activity; // 其他活动

  static BellPeriodKind fromRaw(String raw) {
    switch (raw.toLowerCase()) {
      case 'break':
      case 'breaktime':
        return BellPeriodKind.breakTime;
      case 'lunch':
        return BellPeriodKind.lunch;
      case 'activity':
        return BellPeriodKind.activity;
      default:
        return BellPeriodKind.klass;
    }
  }

  String get raw {
    switch (this) {
      case BellPeriodKind.klass:
        return 'class';
      case BellPeriodKind.breakTime:
        return 'break';
      case BellPeriodKind.lunch:
        return 'lunch';
      case BellPeriodKind.activity:
        return 'activity';
    }
  }
}

/// 作息表里的一个时间格。
class BellPeriod {
  /// 节次序号（1-based，仅 [kind]==klass 时有意义；其余为 0）。
  final int index;
  final BellPeriodKind kind;

  /// 距零点的起止时刻。
  final Duration start;
  final Duration end;

  /// 展示名（如「第1节」「午休」）。
  final String label;

  const BellPeriod({
    required this.index,
    required this.kind,
    required this.start,
    required this.end,
    this.label = '',
  });

  bool get isClass => kind == BellPeriodKind.klass;

  factory BellPeriod.fromJson(Map<String, dynamic> json) {
    return BellPeriod(
      index: asInt(pick(json, ['index', 'Index'])),
      kind: BellPeriodKind.fromRaw(asString(pick(json, ['kind', 'Kind']))),
      start: parseHhmm(pick(json, ['start', 'Start'])) ?? Duration.zero,
      end: parseHhmm(pick(json, ['end', 'End'])) ?? Duration.zero,
      label: asString(pick(json, ['label', 'Label'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'kind': kind.raw,
        'start': durationToHhmm(start),
        'end': durationToHhmm(end),
        if (label.isNotEmpty) 'label': label,
      };
}

/// 作息表：持久共享对象。课程通过节次 [BellPeriod.index] 引用它，改一次作息、
/// 所有引用的课全动。
class BellSchedule {
  final String id;
  final String name;
  final List<BellPeriod> periods;

  const BellSchedule({
    required this.id,
    this.name = '',
    this.periods = const [],
  });

  /// 按节次序号索引的上课格（供课程解析时刻）。
  Map<int, BellPeriod> get classByIndex => {
        for (final p in periods)
          if (p.isClass) p.index: p,
      };

  factory BellSchedule.fromJson(Map<String, dynamic> json, {String? id}) {
    return BellSchedule(
      id: asString(pick(json, ['id', 'Id']) ?? id),
      name: asString(pick(json, ['name', 'Name'])),
      periods: asList(pick(json, ['periods', 'Periods']))
          .whereType<Map>()
          .map((e) => BellPeriod.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        '@type': 'BellSchedule',
        'id': id,
        'name': name,
        'periods': periods.map((e) => e.toJson()).toList(),
      };
}
