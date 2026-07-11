# iOS Live Activity 接入指南（在 Mac 上完成）

本仓库已写好 iOS Live Activity 的全部 Swift 代码，但**新增的 Swift 文件和 Widget Extension target 必须在 Xcode 里手动挂接**（Flutter 生成的工程不会自动纳入新文件）。以下步骤在 **macOS + Xcode 15+** 完成，需 **真机或模拟器 iOS 16.2+**。

本机是 Linux，无法编译/验证 iOS，这部分请你在 Mac 上跑。

## 已提供的文件

App 主 target（Runner）：
- `ios/Runner/ClassActivityAttributes.swift` —— Live Activity 数据模型（**两个 target 共享**）
- `ios/Runner/LiveActivityManager.swift` —— ActivityKit 起/更新/结束 + 边界定时切换
- `ios/Runner/LiveActivityPlugin.swift` —— 复用 `everyclass/live_notification` 通道
- `ios/Runner/AppDelegate.swift` —— 已改：注册上面的插件
- `ios/Runner/Info.plist` —— 已加：`NSSupportsLiveActivities = YES`

Widget Extension target（ClassWidget）：
- `ios/ClassWidget/ClassWidgetBundle.swift` —— `@main` 入口
- `ios/ClassWidget/ClassWidgetLiveActivity.swift` —— 锁屏 + 灵动岛 SwiftUI
- `ios/ClassWidget/Info.plist` —— widget 扩展的 Info.plist

## 步骤

1. **打开工程**：`open ios/Runner.xcworkspace`（用 workspace，不是 xcodeproj）。

2. **把 App 侧新文件加入 Runner target**
   - 右键 Runner 组 → *Add Files to "Runner"…* → 选 `LiveActivityManager.swift`、`LiveActivityPlugin.swift`、`ClassActivityAttributes.swift`。
   - 勾选 *Target Membership → Runner*。（`AppDelegate.swift`、`Info.plist` 已在工程内，无需再加。）

3. **新建 Widget Extension**
   - *File → New → Target… → Widget Extension*，命名 **ClassWidget**。
   - 取消 *Include Configuration App Intent*；若有 *Include Live Activity* 选项则勾选。
   - 弹出 *Activate scheme?* 选 Activate。
   - Xcode 会生成一批模板文件（`ClassWidget.swift`、`ClassWidgetBundle.swift`、`ClassWidgetLiveActivity.swift`、`Info.plist` 等）——**删除这些模板 `.swift`**（移到废纸篓），改用本仓库 `ios/ClassWidget/` 下的同名文件。

4. **把 Widget 侧文件加入 ClassWidget target**
   - *Add Files* 选 `ios/ClassWidget/ClassWidgetBundle.swift`、`ClassWidgetLiveActivity.swift`，Target Membership 勾 **ClassWidget**。
   - 让 Xcode 用 `ios/ClassWidget/Info.plist` 作为该 target 的 Info.plist（Build Settings → *Info.plist File* 指向它，或直接替换模板生成的那份）。

5. **共享模型文件的双 target 成员**
   - 选中 `ClassActivityAttributes.swift`，在右侧 *File Inspector → Target Membership* 同时勾 **Runner** 和 **ClassWidget**。这是 App 与 Widget 共用数据结构的关键。

6. **部署目标与签名**
   - ClassWidget target 的 *Minimum Deployments* 设为 **iOS 16.2**。
   - ClassWidget 的 *Signing & Capabilities*：选择你的 Team，Bundle ID 用 `com.example.everyclass.ClassWidget`（须以 App 的 `com.example.everyclass` 为前缀）。

7. **（可选）App Group**
   - 当前实现通过 MethodChannel 实时下发数据，**不需要** App Group。
   - 若日后做后台 APNs 推送更新，再给 Runner 与 ClassWidget 都加同一个 App Group。

8. **运行验证**
   - 真机/模拟器需 iOS 16.2+，系统 *设置 → 面容 ID 与密码/隐私* 或 App 首次请求时允许「实时活动」。
   - `flutter run`（或 Xcode Run）。在 App 里：导入 ClassIsland 档案 → 到设置页按科目填教室 → 打开「实时通知」开关。
   - 处于「上课中」或临近下一节时，锁屏与灵动岛应出现课程名/教室/教师与**原生倒计时**。

## 说明与后续

- Dart 侧无需区分平台：`lib/platform/live_notification.dart` 通过 `everyclass/live_notification` 通道下发今日课表，Android 走前台服务、iOS 走本插件。
- 当前 iOS 仅在 **App 运行时**更新（`LiveActivityManager` 用定时器在课程边界切换）。**后台自动切换**需接入 APNs 推送（Live Activity `pushType: .token`），属后续里程碑。
- 若灵动岛/锁屏样式要调整，改 `ClassWidgetLiveActivity.swift`。
