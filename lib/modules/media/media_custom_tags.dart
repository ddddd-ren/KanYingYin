/// 本地与网盘共用的自定义标签校验规则。
abstract final class MediaCustomTags {
  static const int maxTagLength = 32;
  static const int maxTags = 30;

  static List<String> normalize(Iterable<Object?> values) {
    final result = <String>[];
    final identities = <String>{};
    for (final value in values) {
      final tag = value?.toString().trim() ?? '';
      if (tag.isEmpty || tag.length > maxTagLength) continue;
      if (!identities.add(tag.toLowerCase())) continue;
      result.add(tag);
      if (result.length == maxTags) break;
    }
    return List<String>.unmodifiable(result);
  }
}
