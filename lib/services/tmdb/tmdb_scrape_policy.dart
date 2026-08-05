import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_resource_name_cleaner.dart';
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
  const TmdbScrapePolicy({
    TmdbResourceNameCleaner cleaner = const TmdbResourceNameCleaner(),
  }) : _cleaner = cleaner;

  final TmdbResourceNameCleaner _cleaner;

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
  TmdbSearchPlan build(
    TmdbScrapeSubject subject,
    TmdbScrapeOptions options,
  ) {
    final queries = <String>[];
    var year = subject.year;
    final sourceCandidates = <String>[
      if (subject.manualSearchTitle?.trim().isNotEmpty == true)
        subject.manualSearchTitle!.trim(),
      ...subject.titleCandidates,
    ];
    for (final candidate in sourceCandidates) {
      year ??= _extractYear(candidate);
      final cleaned = _cleanTitle(candidate, subject: subject);
      if (cleaned.isEmpty) continue;
      if (queries.any(
          (current) => _normalizeQuery(current) == _normalizeQuery(cleaned))) {
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

  String _normalizeQuery(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

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

  String _cleanTitle(
    String value, {
    required TmdbScrapeSubject subject,
  }) {
    var cleaned = _cleaner
        .clean(value)
        .replaceAll(_seasonEpisodePattern, ' ')
        .replaceAll(_chineseSeasonPattern, ' ')
        .replaceAll(_englishSeasonPattern, ' ')
        .replaceAll(_chineseEpisodePattern, ' ')
        .replaceAll(RegExp(r'[（(]\s*[)）]'), ' ')
        .replaceAll(RegExp(r'全\s*\d+\s*集|全集|完结'), ' ')
        .replaceAll(RegExp(r'\s+-\s+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    cleaned = _removeTrailingEpisodeNumber(cleaned, subject);
    cleaned = _removeTrailingSeasonNumber(cleaned, subject);
    final withoutYear = cleaned
        .replaceAll(_yearPattern, ' ')
        .replaceAll(RegExp(r'[（(]\s*[)）]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return withoutYear.isEmpty ? cleaned : withoutYear;
  }

  String _removeTrailingSeasonNumber(
    String value,
    TmdbScrapeSubject subject,
  ) {
    final isTv = subject.mediaEvidence == TmdbMediaEvidence.tv ||
        subject.seasonNumbers.isNotEmpty ||
        subject.episodeNumbers.isNotEmpty;
    if (!isTv || subject.seasonNumbers.length != 1) return value;
    final season = subject.seasonNumbers.single;
    if (season <= 0 || season > 99) return value;
    final suffix = RegExp(r'\s+0?' + season.toString() + r'$');
    final stripped = value.replaceFirst(suffix, '').trim();
    return stripped.isEmpty ? value : stripped;
  }

  String _removeTrailingEpisodeNumber(
    String value,
    TmdbScrapeSubject subject,
  ) {
    final isTv = subject.mediaEvidence == TmdbMediaEvidence.tv ||
        subject.seasonNumbers.isNotEmpty ||
        subject.episodeNumbers.isNotEmpty;
    if (!isTv || subject.episodeNumbers.isEmpty) return value;
    final match = RegExp(r'\s+(\d{1,3})$').firstMatch(value);
    if (match == null) return value;
    final episode = int.tryParse(match.group(1)!);
    if (episode == null || !subject.episodeNumbers.contains(episode)) {
      return value;
    }
    final stripped = value.substring(0, match.start).trim();
    return stripped.isEmpty ? value : stripped;
  }
}
