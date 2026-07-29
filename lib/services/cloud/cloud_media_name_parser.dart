export 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart'
    show TmdbMatchDraft;

import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_resource_name_cleaner.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

class CloudMediaNameParser {
  const CloudMediaNameParser({
    TmdbResourceNameCleaner cleaner = const TmdbResourceNameCleaner(),
  }) : _cleaner = cleaner;

  final TmdbResourceNameCleaner _cleaner;

  static final RegExp _seasonEpisodePattern = RegExp(
    r'\bS(\d{1,2})(?:E(\d{1,3}))?\b',
    caseSensitive: false,
  );
  static final RegExp _chineseSeasonPattern = RegExp(r'第\s*(\d{1,2})\s*季');
  static final RegExp _chineseNamedSeasonPattern = RegExp(
    r'第\s*([零〇一二两三四五六七八九十]{1,3})\s*季',
    unicode: true,
  );
  static final RegExp _englishSeasonPattern = RegExp(
    r'\bSeason\s*(\d{1,2})\b',
    caseSensitive: false,
  );
  static final RegExp _chineseEpisodePattern = RegExp(r'第\s*(\d{1,3})\s*集');
  static final RegExp _yearPattern = RegExp(
    r'(?:^|[\s._(（])((?:19|20)\d{2})(?=$|[\s._)）])',
  );
  TmdbMatchDraft parse({
    required String originalName,
    required bool isDirectory,
    String? preferredTitle,
  }) {
    final source = isDirectory
        ? originalName.trim()
        : originalName.replaceFirst(RegExp(r'\.[^.\\/]+$'), '').trim();
    final seasonEpisode = _seasonEpisodePattern.firstMatch(source);
    final chineseSeason = _chineseSeasonPattern.firstMatch(source);
    final chineseNamedSeason = _chineseNamedSeasonPattern.firstMatch(source);
    final englishSeason = _englishSeasonPattern.firstMatch(source);
    final chineseEpisode = _chineseEpisodePattern.firstMatch(source);
    final preferred = preferredTitle?.trim();
    final titleSource =
        preferred != null && preferred.isNotEmpty ? preferred : source;
    final yearMatch =
        _yearPattern.firstMatch(titleSource) ?? _yearPattern.firstMatch(source);
    final year = yearMatch == null ? null : int.tryParse(yearMatch.group(1)!);
    final searchTitle = _removeYearWhenTitleRemains(
      _cleanTitle(titleSource),
      year,
    );
    final seasonNumber = int.tryParse(
          seasonEpisode?.group(1) ??
              chineseSeason?.group(1) ??
              englishSeason?.group(1) ??
              '',
        ) ??
        _parseChineseNumber(chineseNamedSeason?.group(1));
    final episodeNumber = seasonEpisode?.group(2) ?? chineseEpisode?.group(1);

    return TmdbMatchDraft(
      originalName: originalName,
      searchTitle: searchTitle.isEmpty ? source : searchTitle,
      mediaTypeMode: seasonNumber == null && episodeNumber == null
          ? TmdbMediaTypeMode.auto
          : TmdbMediaTypeMode.tv,
      year: year,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber == null ? null : int.tryParse(episodeNumber),
    );
  }

  String _cleanTitle(String value) {
    return _cleaner
        .clean(value)
        .replaceAll(_seasonEpisodePattern, ' ')
        .replaceAll(_chineseSeasonPattern, ' ')
        .replaceAll(_chineseNamedSeasonPattern, ' ')
        .replaceAll(_englishSeasonPattern, ' ')
        .replaceAll(_chineseEpisodePattern, ' ')
        .replaceAll(RegExp(r'[（(](?:19|20)\d{2}[)）]'), ' ')
        .replaceAll(RegExp(r'全\s*\d+\s*集|全集|完结'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _removeYearWhenTitleRemains(String value, int? year) {
    if (year == null) return value;
    final withoutYear = value
        .replaceAll(RegExp('(?<!\\d)$year(?!\\d)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return withoutYear.isEmpty ? value : withoutYear;
  }

  static int? _parseChineseNumber(String? value) {
    if (value == null || value.isEmpty) return null;
    const digits = <String, int>{
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (!value.contains('十')) {
      final result = digits[value];
      return result == null || result <= 0 ? null : result;
    }
    final parts = value.split('十');
    if (parts.length != 2) return null;
    final tens = parts.first.isEmpty ? 1 : digits[parts.first];
    final ones = parts.last.isEmpty ? 0 : digits[parts.last];
    if (tens == null || ones == null) return null;
    final result = tens * 10 + ones;
    return result >= 1 && result <= 99 ? result : null;
  }
}
