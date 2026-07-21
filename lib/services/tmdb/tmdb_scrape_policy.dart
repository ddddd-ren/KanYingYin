import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

class TmdbSearchPlan {
  TmdbSearchPlan({
    required List<String> queries,
    required this.year,
    required List<TmdbMediaType> mediaTypes,
  })  : queries = List<String>.unmodifiable(queries),
        mediaTypes = List<TmdbMediaType>.unmodifiable(mediaTypes);

  final List<String> queries;
  final int? year;
  final List<TmdbMediaType> mediaTypes;
}

class TmdbScrapePolicy {
  const TmdbScrapePolicy();

  static final RegExp _yearPattern = RegExp(r'(?<!\d)(19|20)\d{2}(?!\d)');
  static final RegExp _seasonEpisodePattern = RegExp(
    r'\bS\d{1,2}(?:\s*E\d{1,3}(?:\s*[-~]\s*E?\d{1,3})?)?\b',
    caseSensitive: false,
  );
  static final RegExp _chineseSeasonPattern = RegExp(
    r'第\s*(?:\d{1,2}|[零〇一二两三四五六七八九十]{1,3})\s*季',
  );
  static final RegExp _englishSeasonPattern = RegExp(
    r'\bSeason\s*\d{1,2}\b',
    caseSensitive: false,
  );
  static final RegExp _chineseEpisodePattern = RegExp(r'第\s*\d{1,3}\s*集');
  static final RegExp _releaseTokenPattern = RegExp(
    r'字幕组|字幕|中字|内嵌|内封|国配|台剧|美剧|日剧|韩剧|web[ ._-]*dl|webrip|blu[ ._-]*ray|bdrip|x26[45]|h26[45]|hevc|av1|ddp?(?:[ ._-]*\d(?:\.\d)?)?|2160p|1080p|720p|4k|8k|uhd|hdr(?:10)?|dolby[ ._-]*vision',
    caseSensitive: false,
  );

  TmdbSearchPlan build(
    TmdbScrapeSubject subject,
    TmdbScrapeOptions options,
  ) {
    final queries = <String>[];
    var year = subject.year;
    for (final candidate in subject.titleCandidates) {
      year ??= _extractYear(candidate);
      final cleaned = _cleanTitle(candidate);
      if (cleaned.isEmpty) continue;
      if (queries.any(
        (current) => current.toLowerCase() == cleaned.toLowerCase(),
      )) {
        continue;
      }
      queries.add(cleaned);
    }

    return TmdbSearchPlan(
      queries: queries,
      year: year,
      mediaTypes: _mediaTypes(subject, options.mediaTypeMode),
    );
  }

  List<TmdbMediaType> _mediaTypes(
    TmdbScrapeSubject subject,
    TmdbMediaTypeMode mode,
  ) {
    return switch (mode) {
      TmdbMediaTypeMode.movie => const <TmdbMediaType>[TmdbMediaType.movie],
      TmdbMediaTypeMode.tv => const <TmdbMediaType>[TmdbMediaType.tv],
      TmdbMediaTypeMode.auto
          when subject.seasonNumbers.isNotEmpty ||
              subject.episodeNumbers.isNotEmpty ||
              subject.mediaEvidence == TmdbMediaEvidence.tv =>
        const <TmdbMediaType>[TmdbMediaType.tv],
      TmdbMediaTypeMode.auto
          when subject.mediaEvidence == TmdbMediaEvidence.movie =>
        const <TmdbMediaType>[TmdbMediaType.movie],
      TmdbMediaTypeMode.auto => const <TmdbMediaType>[
          TmdbMediaType.movie,
          TmdbMediaType.tv,
        ],
    };
  }

  int? _extractYear(String value) {
    final match = _yearPattern.firstMatch(value);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  String _cleanTitle(String value) {
    var result = value
        .replaceFirst(RegExp(r'\.[a-z0-9]{2,5}$', caseSensitive: false), '')
        .replaceAllMapped(RegExp(r'\[([^\]]+)\]|【([^】]+)】'), (match) {
      final content = match.group(1) ?? match.group(2) ?? '';
      return _releaseTokenPattern.hasMatch(content) ? ' ' : ' $content ';
    });
    result = result
        .replaceAll(_seasonEpisodePattern, ' ')
        .replaceAll(_chineseSeasonPattern, ' ')
        .replaceAll(_englishSeasonPattern, ' ')
        .replaceAll(_chineseEpisodePattern, ' ')
        .replaceAll(_yearPattern, ' ')
        .replaceAll(RegExp(r'[（(]\s*[)）]'), ' ')
        .replaceAll(_releaseTokenPattern, ' ')
        .replaceAll(RegExp(r'全\s*\d+\s*集|全集|完结'), ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+-\s+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return result;
  }
}
