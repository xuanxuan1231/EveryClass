# EveryClass · 走班制课表

面向**走班制**（无固定教室）学生的移动课表 App。核心是**系统级实时通知**：在锁屏 / 灵动岛 / 状态栏常驻显示当前与下一节课的**课程名、时间、教室**。

- **iOS**：Live Activity（ActivityKit + WidgetKit，原生倒计时）
- **Android**：常驻前台服务通知；Android 16 用 Live Updates（`ProgressStyle` + 提升为常驻），低版本回退普通常驻通知 + Chronometer 倒计时

课表数据采用受 [JSCalendar (RFC 8984)](https://www.rfc-editor.org/rfc/rfc8984) 启发的自有模型，并可**导入** [ClassIsland](https://github.com/ClassIsland/ClassIsland) 档案 JSON（导入即转换）。设计详见 [`docs/superpowers/specs/2026-07-13-jscalendar-data-model-design.md`](docs/superpowers/specs/2026-07-13-jscalendar-data-model-design.md)。

## 架构

```
lib/
  models/      数据模型（Database → Calendar → BellSchedule / CourseEvent → Meeting；
               WeekRule / OccurrenceOverride / Alert；ClassIsland 中间模型仅供导入）
  data/        仓库（本地 JSON 持久化 database.json + 旧 profile.json 迁移）
               + ClassIsland 导入器 & 转换器
  services/    调度引擎（今日/当前/下一节、周次/单双周轮换、冲突、空闲）+ 设置
  platform/    实时通知 & 文件导入的 MethodChannel 封装
  ui/          日/周视图、课表管理、课程管理、设置页
android/app/src/main/kotlin/...  ScheduleForegroundService（实时通知）
ios/Runner + ios/ClassWidget      Live Activity（见 ios/README.md）
```

数据模型说明：课表按学期存储（一个 `Calendar` = 一学期，自包含作息/课程/例外）；一台设备可存多张课表，「课表管理」支持新建/编辑（名称、颜色、开始日期、备注）/删除/切换使用中的课表，导入 ClassIsland 档案即新增一张；周数由课程排课的周次自动推导（`Calendar.weekCount`），不可手填。用户只需指定**学期第一周**（`Calendar.firstWeekStart`），无需填学期起止。每条排课（`Meeting`）的时间二选一——引用作息表**第 N 节**（跟随作息，改一处全动）或**自定义时刻**（自由，可落在节次网格外）。走班教室存于 `CourseEvent.defaultLocation`（`Meeting.location` / 例外可覆盖）。星期为 1–7（周一=1）。参考：仓库根的 `sample_schedule.json`、`Default.json`。

## 开发

```bash
flutter pub get
flutter analyze
flutter test          # 模型 / 导入器 / 调度引擎 / UI 冒烟测试
flutter run           # 桌面可跑 UI；实时通知需真机
flutter build apk --debug
```

- **Android**：`minSdk 26`，`compile/target 36`。首次运行会请求通知权限；到「设置」导入档案、按科目填教室、打开「实时通知」。
- **iOS**：`ClassWidget` Extension 已接入 Xcode 工程；签名、演示运行与真机验收见 [`ios/README.md`](ios/README.md)。

## 使用

1. 在 ClassIsland 导出档案 JSON。
2. App「设置」→ 导入 ClassIsland 档案（选文件或粘贴）。
3. 按科目填写走班教室（ClassIsland 不含教室）。
4. 在「课表管理」编辑课表，设置学期开始日期（用于单双周轮换）。
5. 打开「实时通知」。

## 现状

M1 数据内核 ✅ · M2 UI ✅ · M3 Android 实时通知（代码 ✅，真机验证中）· M4 iOS Live Activity（代码 ✅，Mac 构建）· M5 周视图 / 开机自恢复（待做）。
