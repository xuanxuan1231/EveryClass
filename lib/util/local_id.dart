/// 生成本地唯一 ID：前缀 + 微秒时间戳（36 进制）。
String newLocalId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
