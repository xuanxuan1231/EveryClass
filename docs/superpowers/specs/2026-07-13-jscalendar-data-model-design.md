# EveryClass 数据模型重构设计（参考 JSCalendar / RFC 8984）

## 目标

用一套受 [JSCalendar (RFC 8984)](https://www.rfc-editor.org/rfc/rfc8984) 启发的数据模型，替换现有的 ClassIsland 对齐模型（`Subjects` / `TimeLayouts` / `ClassPlans` 的位置数组耦合）。新模型要能原生表达：多学期、周次范围、多周轮换、调课/补课/停课例外、逐课程颜色/图标/标签/备注/提醒，并支持 ICS / JSCalendar / JSON 导入导出。

同时保持现有下游契约不变：调度引擎 `ScheduleService` 仍把模型投影成 `ResolvedLesson`，通知与 Live Activity 桥（`everyclass/live_notification`）无需改动。

## 核心设计取舍

### 1. 借用 JSCalendar 的语义，但时间用「节次」符号化，而非绝对时刻

JSCalendar 的 `Event` 用绝对 `start` + `duration` + `recurrenceRules` 描述重复。中国课表以 **星期 + 节次 + 周次** 思考，且「自定义节次时间」要求节次→时刻的映射可随时改。

若把绝对时刻烤进每个事件，改一次作息就得重写所有课程。因此：

- **保留** JSCalendar 的重复语义（星期、间隔=轮换周期、周次范围、`recurrenceOverrides` 例外）。
- **替换** 时间维度：课程不存绝对 `start`，而是引用 `(bellScheduleId, 起始节, 结束节)`，在计算时对作息表求解出当天绝对时刻。这直接支撑「自定义节次时间」「空闲时间计算」。

导出 ICS / JSCalendar 时，再用作息表把节次解析成绝对 `start` + `duration` + `RRULE`。

### 2. 两层：`CourseEvent`（课程语义） + `Meeting`（一次周期性排课）

纯 JSCalendar 里每个 `Event` 是一条重复序列，多个上课时段要么拆成多个 Event 靠 `relatedTo` 关联，要么用 `BYDAY`。但一门课不同星期节次不同（语文 周一1-2、周三3-4），且学生按「一门课」思考。故：

- `CourseEvent` = 课程语义聚合：名称、颜色、图标、教师、标签、备注、默认地点、默认提醒。≈ 一组共享元数据的 JSCalendar Event（JSCalendar 原生用 `relatedTo: {parent}` 表达，本模型用显式容器）。
- `Meeting` = 一条周期性排课：星期 + 节次范围 + 周次规则 + 可选地点/教师覆盖。每个 `Meeting` ≈ 一条 JSCalendar 重复序列。

### 3. 例外（调课/补课/停课）用 `recurrenceOverrides`

对齐 JSCalendar：以「原本发生日期」为键的补丁表。停课 = `excluded`；改教室/改时间 = 局部 patch；补课（规则不生成的额外日期）= 在 overrides 里新增一个 occurrence（RFC 8984 允许 override 添加规则外的实例）。

---

## 对象模型

顶层是 `Database`：持有多个 `Calendar`（多学期），当前选中一个。每个 `Calendar` 自包含（作息、课程、例外都在内），满足「课表按一个学期存储」。

```
Database
 ├─ schemaVersion: int
 ├─ selectedCalendarId: Id
 └─ calendars: { Id → Calendar }
```

### Calendar（学期课表）

```jsonc
{
  "@type": "Calendar",
  "id": "2025-fall",
  "name": "2025 秋季学期",
  "timeZone": "Asia/Shanghai",
  "firstWeekStart": "2025-09-01",   // 用户显式指定的「第一周」周一；无需 term start/end
  "totalWeeks": 20,                  // 可选；缺省从各 Meeting 周次范围推导
  "color": "#4C6EF5",                // 学期主题色（可选）
  "bellSchedules": { "Id": BellSchedule },
  "weekdayBellSchedule": { "1": "bs-weekday", "6": "bs-saturday" }, // 可选：按星期指派作息
  "defaultBellScheduleId": "bs-weekday",
  "courses": { "Id": CourseEvent },
  "extra": {}                         // 厂商扩展 / 未来字段透传
}
```

- **不要求**用户填学期起止；只需 `firstWeekStart`。周次范围与 `totalWeeks` 决定有效区间。
- `firstWeekStart` 支撑「多周轮换」「周次范围」的绝对日期换算。
- 多课表 = 多个 `Calendar`。

### BellSchedule（作息 / 时间表）

取代 `TimeLayout`。节次是一等概念，含课间/午休便于「空闲时间计算」。

```jsonc
{
  "@type": "BellSchedule",
  "id": "bs-weekday",
  "name": "工作日作息",
  "periods": [
    { "index": 1, "kind": "class", "start": "08:00", "end": "08:45", "label": "第1节" },
    { "index": 0, "kind": "break", "start": "08:45", "end": "08:55" },
    { "index": 2, "kind": "class", "start": "08:55", "end": "09:40", "label": "第2节" },
    { "index": 0, "kind": "lunch", "start": "11:40", "end": "14:00" }
  ]
}
```

- `kind`: `class | break | lunch | activity`。只有 `class` 参与节次编号（`index` 1-based）。
- `Meeting` 用 `startPeriod`/`endPeriod` 引用 `index`；改作息不动课程。

**时间模型（定稿）**：每条 `Meeting` 的时间是**二选一**——
1. **引用作息表节次**：填 `startPeriod`/`endPeriod`（引用 `BellSchedule`），时刻跟随作息，改一次作息、所有引用的课全动。这是「存一份作息表、选第N节」的场景。
2. **自定义时刻**：填 `customStart`/`customEnd`（`"HH:mm"`），该课存绝对时刻、不再跟随作息，可落在节次网格之外（晚自习、补课、大学参差课时）。

判定规则：`customStart != null` → 用自定义时刻；否则用 `(bellScheduleId, startPeriod, endPeriod)` 求解。作息表是**持久共享对象**，不是一次性快捷填充。

### CourseEvent（课程）

```jsonc
{
  "@type": "CourseEvent",
  "id": "c-math",
  "title": "高等数学",                 // 课程名称
  "color": "#F03E3E",                 // 课程颜色（JSCalendar: color）
  "icon": "function",                 // 课程图标（扩展）
  "teacher": "李老师",                // 便捷字段；JSCalendar 语义等价 participants[owner]
  "defaultLocation": "教三-201",      // 一学期基本不变的地点（走班；JSCalendar: locations）
  "keywords": ["必修", "考试"],        // 标签（JSCalendar: keywords，集合）
  "description": "带计算器",           // 备注（JSCalendar: description）
  "alerts": { "Id": Alert },          // 课程级默认提醒
  "meetings": [ Meeting ],            // 一门课的多个周期性时段
  "extra": {}
}
```

### Meeting（周期性排课）

```jsonc
{
  "@type": "Meeting",
  "id": "m1",
  "weekday": 1,                       // 星期，1–7（周一=1，对齐 DateTime.weekday）
  "startPeriod": 1,                   // 起始节（引用 BellSchedule.periods[].index）；自定义时刻时为 0
  "endPeriod": 2,                     // 结束节（含）；自定义时刻时为 0
  "customStart": null,                // "HH:mm"；非空则用自定义时刻，忽略节次/作息
  "customEnd": null,                  // "HH:mm"
  "bellScheduleId": null,             // 可选覆盖；null=用 Calendar 的星期/默认作息
  "weeks": WeekRule,                  // 周次范围 + 多周轮换
  "location": null,                   // 可选覆盖 CourseEvent.defaultLocation（走班个别调整）
  "teacher": null,                    // 可选覆盖
  "overrides": { "2025-10-06": OccurrenceOverride }, // 调课/补课/停课，键=原发生日期
  "extra": {}
}
```

### WeekRule（周次规则）

一个紧凑描述，覆盖「每周 / 单双周 / 周次范围 / N 周轮换 / 显式周列表」，且可无损转 JSCalendar `RecurrenceRule`。

```jsonc
{
  "interval": 1,          // 1=每周；2=单/双周；N=N周轮换周期长度  → RRULE INTERVAL
  "offset": 0,            // 在周期内第几周生效，0-based（单周=0，双周=1）
  "range": { "from": 1, "to": 16 },  // 周次范围（含，1-based 学期周）→ 决定首次/UNTIL
  "include": null         // 可选：显式周列表 [1,3,5]，非空时忽略 interval/offset → RDATE
}
```

判定第 W 周（1-based）是否生效：
`range.from ≤ W ≤ range.to` 且（`include` 非空 → `W ∈ include`；否则 `(W - 1) % interval == offset`）。

### OccurrenceOverride（单次例外：调课/补课/停课）

键为该次课「原本的日期」（`yyyy-MM-dd`）。对齐 JSCalendar `recurrenceOverrides` 的 PatchObject 语义。

```jsonc
// 停课
{ "excluded": true }

// 改教室 / 改教师
{ "location": "实验楼-305", "teacher": "王老师" }

// 调课（改到同日不同节次，或改到别的日期）
{ "movedToDate": "2025-10-11", "startPeriod": 3, "endPeriod": 4 }

// 补课（规则外新增一次；键为补课当天日期，added=true）
{ "added": true, "startPeriod": 5, "endPeriod": 6, "location": "教一-101" }
```

### Alert（提醒）

对齐 JSCalendar `Alert` + `OffsetTrigger`，与已实现的通知提前量一致。

```jsonc
{
  "@type": "Alert",
  "trigger": { "@type": "OffsetTrigger", "relativeTo": "start", "offset": "-PT5M" },
  "action": "display"
}
```

`relativeTo`: `start | end`；`offset` 为 ISO-8601 时长（负=之前）。全局默认提醒开关仍由 `SettingsService` 管，课程级 `alerts` 覆盖之。

---

## 需求覆盖对照

| 信息 | 落点 |
|---|---|
| 课程 ID | `CourseEvent.id` |
| 课程名称 | `CourseEvent.title` |
| 颜色/图标 | `CourseEvent.color` / `.icon` |
| 任课教师 | `CourseEvent.teacher`（`Meeting.teacher` 可覆盖） |
| 上课地点（含例外） | `CourseEvent.defaultLocation`；`Meeting.location`；`OccurrenceOverride.location` |
| 开始/结束时间 | 由 `Meeting.(startPeriod,endPeriod)` + `BellSchedule` 求解 |
| 节次 | `BellSchedule.periods[].index` + `Meeting.startPeriod/endPeriod` |
| 星期 | `Meeting.weekday` |
| 周次范围 | `WeekRule.range` |
| 多周轮换 | `WeekRule.interval` + `.offset`（或 `.include`） |
| 学期 | `Calendar`（多个=多学期） |
| 重复规则 | `WeekRule`（可转 JSCalendar RRULE） |
| 调课/补课 | `OccurrenceOverride.movedToDate` / `.added` |
| 停课/例外日期 | `OccurrenceOverride.excluded` |
| 提醒 | `CourseEvent.alerts` / `Alert` + 全局 `SettingsService` |
| 备注 | `CourseEvent.description` |
| 标签 | `CourseEvent.keywords` |

| 功能 | 实现要点 |
|---|---|
| 多课表（多学期） | `Database.calendars` + `selectedCalendarId` |
| 自定义节次时间 | `BellSchedule`（节次符号化，改作息不动课程） |
| 冲突检测 | 新增 `ConflictService`：对解析后的 occurrence 按 (日期, 节次区间) 检测重叠 |
| 空闲时间计算 | 遍历 `BellSchedule` 节次减去已占用区间 |
| 今日/下一节 | `ScheduleService.currentLesson/nextLesson`（沿用，改内核） |
| 搜索与筛选 | 对 `courses` 按 title/teacher/keywords/location 过滤 |
| 导入/导出 | 见下 |
| 通知提醒 | 已实现；`Alert` 提供数据源 |
| Live Activity | 已实现；下游 `ResolvedLesson` 契约不变 |
| 插件/自定义字段 | 各对象 `extra` + `everyclass:*` 扩展命名空间 |

## 调度引擎改造

`ScheduleService.scheduleFor(day)` 新内核（输出仍是 `List<ResolvedLesson>`，UI/通知零改动）：

1. 由 `Calendar.firstWeekStart` 算出 `day` 的 1-based 学期周 `W` 与 `weekday`。
2. 遍历所有 `CourseEvent.meetings`，先取 `weekday` 命中、`WeekRule` 命中的；对 `day` 查 `overrides`（停课跳过、调课改节次/搬走、改教室覆盖）；再并入当天 `added` 的补课。
3. 用 `BellSchedule`（`Meeting.bellScheduleId` → `Calendar.weekdayBellSchedule[weekday]` → `defaultBellScheduleId`）把 `startPeriod..endPeriod` 解析成 `start/end`，产出 `ResolvedLesson`（补 `subject`/`room`/`period`）。

`ResolvedLesson` 可加可选 `color`/`endPeriod`，但保持向后兼容。

## 导入 / 导出

- **原生 JSON**：模型自身序列化，无损往返。
- **JSCalendar**：每个 `Meeting` → 一个 `Event`：`start`(首次绝对时刻) + `duration`(节次时长) + `recurrenceRules`(WeekRule→RRULE) + `recurrenceOverrides`(OccurrenceOverride) + `alerts` + `color` + `keywords` + `locations`；同课的多个 Event 用 `relatedTo` 关联。反向解析对称。
- **ICS**：由 JSCalendar 再降级为 `VEVENT` + `RRULE` + `EXDATE`/`RDATE` + `VALARM`。
- **ClassIsland**（遗留兼容）：保留 `ClassIslandImporter`，转换为新模型的 legacy 适配层（`TimeLayout→BellSchedule`、`ClassPlan.timeRule→WeekRule`、位置数组→`Meeting`）。

## 迁移

1. 新增 `models/`（`calendar`/`bell_schedule`/`course_event`/`meeting`/`week_rule`/`occurrence_override`/`alert`），保留 `resolved_lesson`。
2. `ScheduleService` 换内核，签名与产物不变。
3. `LocalProfileRepository` → `LocalDatabaseRepository`（新文件名 + 一次性从旧 `profile.json` 迁移）。
4. ClassIsland 导入改为「导入即转换」。
5. `platform/live_notification.dart` 与 iOS/Android 原生层不动。

## 开放问题（已定稿）

- **作息表归属**：作息表是**持久共享对象**，存在 `Calendar` 内；每条 `Meeting` 可引用节次（跟随作息）或填自定义时刻（自由）。
- **教师**：用便捷 `teacher` 字符串，不引入 `participants` 结构；多教师等复杂场景挂 `extra`。
- **ClassIsland**：**仅导入**（导入即转换为新模型）；不再以 ClassIsland 格式持久化或导出。
</content>
</invoke>
