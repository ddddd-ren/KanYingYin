/// 仅用于旧 Hive 二进制兼容，活动业务不得引用。
final class LegacyBangumiTag {
  const LegacyBangumiTag({
    required this.name,
    required this.count,
    required this.totalCount,
  });

  final String name;
  final int count;
  final int totalCount;
}
