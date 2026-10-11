import 'package:synchronized/synchronized.dart';

// 备份导入与普通用户记录写入共用锁，避免回滚覆盖期间的新操作。
final Lock userDataMutationLock = Lock(reentrant: true);
