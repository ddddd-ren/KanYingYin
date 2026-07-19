import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

@immutable
class TmdbMatchDraft {
  const TmdbMatchDraft({
    required this.originalName,
    required this.searchTitle,
    required this.mediaTypeMode,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String originalName;
  final String searchTitle;
  final TmdbMediaTypeMode mediaTypeMode;
  final int? year;
  final int? seasonNumber;
  final int? episodeNumber;
}

class CloudMediaNameParser {
  const CloudMediaNameParser();

  static final RegExp _seasonEpisodePattern = RegExp(
    r'\bS(\d{1,2})(?:E(\d{1,3}))?\b',
    caseSensitive: false,
  );
  static final RegExp _chineseSeasonPattern = RegExp(r'第\s*(\d{1,2})\s*季');
  static final RegExp _chineseEpisodePattern = RegExp(r'第\s*(\d{1,3})\s*集');
  static final RegExp _yearPattern = RegExp(
    r'(?:^|[\s._(（])((?:19|20)\d{2})(?=$|[\s._)）])',
  );
  static final RegExp _releaseTokenPattern = RegExp(
    r'字幕组|字幕|中字|国配|台剧|美剧|日剧|韩剧|web-?dl|bluray|x26[45]|h26[45]|hevc|ddp(?:[\s._-]*\d(?:\.\d)?)?|2160p|1080p|720p|4k|8k|uhd|hdr(?:10)?',
    caseSensitive: false,
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
    final chineseEpisode = _chineseEpisodePattern.firstMatch(source);
    final preferred = preferredTitle?.trim();
    final titleSource =
        preferred != null && preferred.isNotEmpty ? preferred : source;
    final yearMatch =
        _yearPattern.firstMatch(titleSource) ?? _yearPattern.firstMatch(source);
    final searchTitle = _cleanTitle(titleSource);
    final seasonNumber = seasonEpisode?.group(1) ?? chineseSeason?.group(1);
    final episodeNumber = seasonEpisode?.group(2) ?? chineseEpisode?.group(1);

    return TmdbMatchDraft(
      originalName: originalName,
      searchTitle: searchTitle.isEmpty ? source : searchTitle,
      mediaTypeMode: seasonNumber == null && episodeNumber == null
          ? TmdbMediaTypeMode.auto
          : TmdbMediaTypeMode.tv,
      year: yearMatch == null ? null : int.tryParse(yearMatch.group(1)!),
      seasonNumber: seasonNumber == null ? null : int.tryParse(seasonNumber),
      episodeNumber: episodeNumber == null ? null : int.tryParse(episodeNumber),
    );
  }

  String _cleanTitle(String value) {
    var result = value.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]|【([^】]+)】'),
      (match) {
        final content = match.group(1) ?? match.group(2) ?? '';
        return _releaseTokenPattern.hasMatch(content) ? ' ' : match.group(0)!;
      },
    );
    result = result
        .replaceAll(_seasonEpisodePattern, ' ')
        .replaceAll(_chineseSeasonPattern, ' ')
        .replaceAll(_chineseEpisodePattern, ' ')
        .replaceAll(RegExp(r'[（(](?:19|20)\d{2}[)）]'), ' ')
        .replaceAll(_releaseTokenPattern, ' ')
        .replaceAll(RegExp(r'全\s*\d+\s*集|全集|完结'), ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return result;
  }
}
