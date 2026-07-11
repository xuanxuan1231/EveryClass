import '../models/profile.dart';

/// 档案持久化的抽象接口——本地实现见 [LocalProfileRepository]，未来可换成
/// 网络同步实现而不影响上层。
abstract class ProfileRepository {
  /// 读取已保存的档案；无则返回 null。
  Future<Profile?> load();

  /// 覆盖保存档案。
  Future<void> save(Profile profile);

  /// 清除已保存的档案。
  Future<void> clear();
}
