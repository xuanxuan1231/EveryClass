import 'package:flutter/services.dart';

/// 通过原生 SAF（Android `ACTION_OPEN_DOCUMENT`）选择并读取一个 JSON 文件的文本。
///
/// 用自建 MethodChannel 而非第三方插件，避免额外依赖与 KGP 兼容问题。未实现的平台
/// （桌面/测试）返回 null，由调用方回退到「粘贴 JSON」。
class FileImport {
  static const MethodChannel _channel = MethodChannel('everyclass/io');

  /// 返回所选文件文本；用户取消或平台不支持时返回 null。
  static Future<String?> pickJsonText() async {
    try {
      return await _channel.invokeMethod<String>('pickJson');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
