
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { updateAllForms } from '../cardcommon/CardData';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
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
}
