import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';

class CloudWorkGroupingPolicy {
  const CloudWorkGroupingPolicy();

  String? matchedGroupKey(
    String sourceId,
    CloudWorkTmdbRecord? record,
  ) {
    final metadata = record?.metadata;
    if (record?.status != CloudWorkTmdbStatus.matched || metadata == null) {
      return null;
    }
    return '$sourceId|tmdb|${metadata.mediaType.name}|${metadata.id}';
  }

  Set<String> titleAliases({
    required Iterable<String?> candidates,
    required Iterable<int> seasonNumbers,
  }) {
    final seasons = seasonNumbers.where((season) => season > 0).toSet();
    final aliases = <String>{};
    for (final candidate in candidates) {
      final normalized = _normalizeTitle(candidate, seasons);
      if (normalized.isNotEmpty) aliases.add(normalized);
    }
    return Set<String>.unmodifiable(aliases);
  }

  String _normalizeTitle(String? value, Set<int> seasonNumbers) {
    var normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return normalized;
    normalized = normalized
        .replaceAll(RegExp(r'\[[^\]]*\]|【[^】]*】'), ' ')
        .replaceAll(RegExp(r'第\s*[0-9一二三四五六七八九十百]+\s*[季期部篇章]'), ' ')
        .replaceAll(RegExp(r'\b(?:season|series|s)\s*0*(\d{1,2})\b'), ' ')
        .replaceAll(RegExp(r'[._\-:：·!！?？,，、~～()（）]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (seasonNumbers.length == 1) {
      final season = seasonNumbers.single;
      normalized = normalized
          .replaceFirst(RegExp(r'\s+0?' + season.toString() + r'\s*$'), '')
          .trim();
    }
    return normalized.replaceAll(' ', '');
  }
}
