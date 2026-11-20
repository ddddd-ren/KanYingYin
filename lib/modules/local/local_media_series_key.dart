/// 作品键同时保存来源、原分组和已知的匹配身份；展示名只用于区分拆开的子组。
abstract final class LocalMediaSeriesKey {
  static String build({
    required String sourceId,
    required String title,
    required String? tmdbIdentity,
    String? part,
  }) =>
      [
        Uri.encodeComponent(sourceId),
        'work',
        Uri.encodeComponent(title.toLowerCase()),
        Uri.encodeComponent(tmdbIdentity ?? ''),
        if (part != null) Uri.encodeComponent(part),
      ].join('|');

  /// 旧标签只有分组标题，有的带来源前缀，需在完整索引中检查唯一归属。
  static Iterable<String> legacyTagKeys(String key) sync* {
    final parts = key.split('|');
    if (parts.length < 2) return;
    final scopedWork = parts.length >= 4 && parts[1] == 'work';
    final title = scopedWork
        ? Uri.decodeComponent(parts[2])
        : key.substring(parts.first.length + 1);
    yield title;
    yield '${parts.first}|$title';
    if (scopedWork && parts[3].isNotEmpty) {
      // 首次匹配后，未识别时保存的标签也需按唯一归属迁移。
      parts[3] = '';
      yield parts.join('|');
    }
  }
}
