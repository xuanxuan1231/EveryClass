# EveryClass · 走班制课表

面向**走班制**（无固定教室）学生的移动课表 App。核心是**系统级实时通知**：在锁屏 / 灵动岛 / 状态栏常驻显示当前与下一节课的**课程名、时间、教室**。

- **iOS**：Live Activity（ActivityKit + WidgetKit，原生倒计时）
- **Android**：常驻前台服务通知；Android 16 用 Live Updates（`ProgressStyle` + 提升为常驻），低版本回退普通常驻通知 + Chronometer 倒计时

课表数据对齐 [ClassIsland](https://github.com/ClassIsland/ClassIsland) 的 schema，通过导入其档案 JSON 使用。

## 架构

```
lib/
  models/      数据模型（ClassIsland 对齐 + 走班教室扩展）
  data/        仓库（本地 JSON 持久化）+ ClassIsland 导入器
  services/    调度引擎（今日/当前/下一节、单双周轮换）+ 设置
  platform/    实时通知 & 文件导入的 MethodChannel 封装
  ui/          今日课表、设置页
android/app/src/main/kotlin/...  ScheduleForegroundService（实时通知）
ios/Runner + ios/ClassWidget      Live Activity（见 ios/LIVE_ACTIVITY_SETUP.md）
```

数据模型说明：ClassIsland 无教室字段，走班教室存于 `Subject.defaultRoom` / `ClassInfo.room`，并镜像进 `AttachedObjects["everyclass.room"]` 以保持档案往返兼容。`TimeRule.WeekDay` 为 1–7（周一=1）。参考：仓库根的 `Default.json`（空课表样例）与 `profile_schema_detailed.txt`。

## 开发

```bash
flutter pub get
flutter analyze
flutter test          # 模型 / 导入器 / 调度引擎 / UI 冒烟测试
flutter run           # 桌面可跑 UI；实时通知需真机
flutter build apk --debug
```

- **Android**：`minSdk 26`，`compile/target 36`。首次运行会请求通知权限；到「设置」导入档案、按科目填教室、打开「实时通知」。
- **iOS**：Live Activity 需在 macOS + Xcode 上挂接 Widget Extension，详见 [`ios/LIVE_ACTIVITY_SETUP.md`](ios/LIVE_ACTIVITY_SETUP.md)。

## 使用

1. 在 ClassIsland 导出档案 JSON。
2. App「设置」→ 导入 ClassIsland 档案（选文件或粘贴）。
3. 按科目填写走班教室（ClassIsland 不含教室）。
4. 设置学期开始日期（用于单双周轮换）。
5. 打开「实时通知」。

## 现状

M1 数据内核 ✅ · M2 UI ✅ · M3 Android 实时通知（代码 ✅，真机验证中）· M4 iOS Live Activity（代码 ✅，Mac 构建）· M5 周视图 / 开机自恢复（待做）。
