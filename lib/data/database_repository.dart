import '../models/database.dart';

/// 数据库持久化的抽象接口——本地实现见 [LocalDatabaseRepository]，未来可换成
/// 网络同步实现而不影响上层。
abstract class DatabaseRepository {
  /// 读取已保存的数据库；无则返回 null。
  Future<Database?> load();

  /// 覆盖保存数据库。
  Future<void> save(Database database);

  /// 清除已保存的数据库。
  Future<void> clear();
}
