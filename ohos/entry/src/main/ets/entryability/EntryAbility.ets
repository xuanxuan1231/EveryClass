
import { FlutterAbility, FlutterEngine, MethodChannel, MethodCall, MethodResult, MethodCallHandler } from '@ohos/flutter_ohos';
import type { Want, AbilityConstant } from '@kit.AbilityKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { updateAllForms } from '../cardcommon/CardData';

// 点课深链通道名：与 Flutter 侧 lib/platform/widget_deeplink.dart 约定，跨平台一致
// （Android 的 MainActivity 用同名通道）。卡片点课 → 本 Ability 解析 Want → 经此
// 通道把 { subjectId, startMinute } 转交 Dart，定位该课并唤出详情浮窗。
const DEEPLINK_CHANNEL = 'everyclass/deeplink';

export default class EntryAbility extends FlutterAbility implements MethodCallHandler {
  // 冷启动路径：把启动 Want 解析出的课程身份暂存，等 Dart 侧 getInitialLesson 来取。
  private pendingLesson: Record<string, Object> | null = null;
  // 热启动路径（应用已在前台又点课）：经此通道直接推 openLesson 给 Dart。
  private deeplinkChannel: MethodChannel | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 先解析再交给框架：确保 configureFlutterEngine 注册通道处理器时 pendingLesson 已就绪。
    this.pendingLesson = this.parseLessonWant(want);
    super.onCreate(want, launchParam);
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 点课深链通道：Dart 启动后调 getInitialLesson 取一次冷启动的点课（见 onCreate）。
    this.deeplinkChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(),
      DEEPLINK_CHANNEL,
    );
    this.deeplinkChannel.setMethodCallHandler(this);
  }

  // MethodCallHandler：仅处理 getInitialLesson（冷启动兜底），其余交回 Dart。
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getInitialLesson') {
      result.success(this.pendingLesson);
      this.pendingLesson = null;
    } else {
      result.notImplemented();
    }
  }

  // 应用已在前台时又点课（热启动路径）：直接经通道推给 Dart；通道尚未就绪则暂存兜底。
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    const lesson = this.parseLessonWant(want);
    if (lesson == null) {
      return;
    }
    if (this.deeplinkChannel != null) {
      this.deeplinkChannel.invokeMethod('openLesson', lesson);
    } else {
      this.pendingLesson = lesson;
    }
  }

  // 退到后台（用户改完课表回到桌面）时，用 Flutter 刚写好的最新快照立即刷新
  // 桌面上的服务卡片，实现「改完即刷新」。
  //
  // 先调用 super.onBackground()（内部走 Flutter 引擎的 onHide），再做卡片刷新，
  // 并且刷新整体吞异常，确保绝不影响 App 自身的渲染/生命周期。
  //
  // 排障提示：若怀疑黑屏/花屏与卡片有关，把下面这个方法整体注释掉重试即可
  // 排除——App 渲染与本方法无关时，注释后黑屏依旧。
  onBackground(): void {
    super.onBackground()
    try {
      updateAllForms(this.context)
    } catch (e) {
    }
  }

  /// 从卡片点课的 Want 里提取课程身份；非点课（普通启动/打开应用）返回 null。
  /// 卡片以 postCardAction 传 { targetPage:'lesson', subjectId, startMinute }，
  /// 这些落在 want.parameters 上。
  private parseLessonWant(want: Want): Record<string, Object> | null {
    const params = want.parameters;
    if (!params) {
      return null;
    }
    if (params['targetPage'] !== 'lesson') {
      return null;
    }
    const sidRaw = params['subjectId'];
    const sid = typeof sidRaw === 'string' ? sidRaw as string : '';
    let start = -1;
    const startRaw = params['startMinute'];
    if (typeof startRaw === 'number') {
      start = startRaw as number;
    } else if (typeof startRaw === 'string') {
      const n = Number.parseInt(startRaw as string, 10);
      if (!Number.isNaN(n)) {
        start = n;
      }
    }
    if (sid.length === 0 && start < 0) {
      return null;
    }
    const lesson: Record<string, Object> = { 'subjectId': sid, 'startMinute': start };
    return lesson;
  }
}
