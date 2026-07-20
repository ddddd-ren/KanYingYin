import 'package:kanyingyin/modules/local/local_episode_info.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/services/media_name_analyzer.dart';
import 'package:path/path.dart' as p;

class LocalEpisodeParser {
  LocalEpisodeParser({MediaNameAnalyzer? nameAnalyzer})
      : _nameAnalyzer = nameAnalyzer ?? const MediaNameAnalyzer();

  static final _releaseGroupPattern = RegExp(
    r'^[\[\(\u3010\u300c\uff08](?<group>[^\]\)\u3011\u300d\uff09]{2,32})[\]\)\u3011\u300d\uff09]',
    unicode: true,
  );

  static final _resolutionPattern = RegExp(
    r'\b(?<resolution>480p|720p|1080p|1440p|2160p|4k|8k)\b',
    caseSensitive: false,
  );

  static final _sourcePattern = RegExp(
    r'\b(?<source>WEB-DL|WEBRip|BDRip|BluRay|BD|TVRip|HDTV)\b',
    caseSensitive: false,
  );

  static final _codecPattern = RegExp(
    r'\b(?<codec>x264|x265|h264|h265|hevc|avc|av1)\b',
    caseSensitive: false,
  );

  static final _seasonEpisodePattern = RegExp(
    r'^(?<series>.+?)[\s._\-\[\(]*S(?<season>\d{1,2})E(?<episode>\d{1,3})(?!\d)(?<title>.*)$',
    caseSensitive: false,
  );

  static final _chineseSeasonEpisodePattern = RegExp(
    r'^(?<series>.+?)[\s._\-]*\u7b2c\s*(?<season>\d{1,2})(?!\d)\s*[\u5b63\u90e8][\s._\-]*\u7b2c\s*(?<episode>\d{1,3})(?!\d)\s*[\u8bdd\u8a71\u96c6](?<title>.*)$',
    caseSensitive: false,
    unicode: true,
  );

  static final _chineseEpisodePattern = RegExp(
    r'^(?<series>.+?)(?:[\s._\-]+\u7b2c\s*|[\s._\-]+|\u7b2c\s*)(?<episode>\d{1,3})(?!\d)\s*[\u8bdd\u8a71\u96c6](?<title>.*)$',
    caseSensitive: false,
    unicode: true,
  );

  static final _englishEpisodePattern = RegExp(
    r'^(?<series>.+?)[\s._\-]*(EP|E|Episode)\s*(?<episode>\d{1,3})(?!\d)(?<title>.*)$',
    caseSensitive: false,
  );

  static final _bracketedEpisodePattern = RegExp(
    r'^(?<series>.+?)\[(?<episode>\d{1,3})\](?<title>.*)$',
    caseSensitive: false,
  );

  static final _bareEpisodePattern = RegExp(
    r'^(?<series>.+?)[\s._\-\[](?<episode>\d{1,3})(?!\d)(?<title>.*)$',
    caseSensitive: false,
  );

  static final _patterns = <RegExp>[
    _seasonEpisodePattern,
    _chineseSeasonEpisodePattern,
    _chineseEpisodePattern,
    _englishEpisodePattern,
    _bracketedEpisodePattern,
    _bareEpisodePattern,
  ];

  final MediaNameAnalyzer _nameAnalyzer;

  LocalEpisodeInfo? parse(String filePath) {
    final fileName = p.basenameWithoutExtension(filePath);
    final normalized = _normalizeName(fileName);
    final shared = _nameAnalyzer.analyze(
      p.basename(filePath),
      isDirectory: false,
    );
    final seasonFromDirectory = _seasonFromDirectory(filePath);
    final releaseGroup =
        _extractNamed(normalized, _releaseGroupPattern, 'group');
    final resolution = shared.releaseTags.resolution ??
        _extractNamed(normalized, _resolutionPattern, 'resolution');
    final source = shared.releaseTags.source ??
        _extractNamed(normalized, _sourcePattern, 'source');
    final codec = shared.releaseTags.codec ??
        _extractNamed(normalized, _codecPattern, 'codec');
    for (final pattern in _patterns) {
      final match = pattern.firstMatch(normalized);
      if (match == null) continue;

      final episodeText = _namedGroup(match, 'episode');
      final episodeNumber = int.tryParse(episodeText ?? '');
      if (episodeNumber == null || episodeNumber <= 0) continue;

      final rawSeries = _namedGroup(match, 'series') ?? '';
      final title = _cleanEpisodeTitle(_namedGroup(match, 'title') ?? '');
      if (shared.role == MediaNodeRole.work &&
          seasonFromDirectory == null &&
          title.isEmpty) {
        continue;
      }
      if (identical(pattern, _bareEpisodePattern) &&
          _shouldSkipBareEpisode(
            rawSeries: rawSeries,
            normalized: normalized,
            episodeNumber: episodeNumber,
            title: title,
          )) {
        continue;
      }

      final seriesName = _resolveSeriesName(
        rawSeries: rawSeries,
        filePath: filePath,
        releaseGroup: releaseGroup,
      );
      if (seriesName.isEmpty) continue;

      final seasonNumber = int.tryParse(_namedGroup(match, 'season') ?? '') ??
          seasonFromDirectory;
      return LocalEpisodeInfo(
        seriesName: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        episodeTitle: title.isEmpty ? null : title,
        releaseGroup: releaseGroup,
        resolution: _canonicalResolution(resolution),
        source: _canonicalSource(source),
        codec: _canonicalCodec(codec),
      );
    }
    return null;
  }

  bool _shouldSkipBareEpisode({
    required String rawSeries,
    required String normalized,
    required int episodeNumber,
    required String title,
  }) {
    if (RegExp(r'^\s*周年', unicode: true).hasMatch(title)) {
      return true;
    }
    if (title.trim().isEmpty && _looksLikeMovieLikeTitle(rawSeries)) {
      return true;
    }
    if (episodeNumber != 4 && episodeNumber != 8) return false;
    final lower = normalized.toLowerCase();
    final hasResolutionToken = lower.contains('4k') || lower.contains('8k');
    if (!hasResolutionToken) return false;
    final trimmedTitle = title.trimLeft().toLowerCase();
    return trimmedTitle.startsWith('k');
  }

  bool _looksLikeMovieLikeTitle(String value) {
    return RegExp(r'\b(19|20)\d{2}\b').hasMatch(value) ||
        RegExp(
          r'\b(4k|8k|1080p|1440p|2160p|web\s*[- ]?dl|webrip|bdrip|bluray|hdtv|tvrip|hq|dt|x264|x265|hevc|avc|av1|aac|flac)\b',
          caseSensitive: false,
          unicode: true,
        ).hasMatch(value);
  }

  String? _extractNamed(String value, RegExp pattern, String name) {
    final match = pattern.firstMatch(value);
    if (match == null || !match.groupNames.contains(name)) return null;
    final text = match.namedGroup(name)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? _namedGroup(RegExpMatch match, String name) {
    if (!match.groupNames.contains(name)) return null;
    return match.namedGroup(name);
  }

  String _normalizeName(String value) {
    return value
        .replaceAll(RegExp(r'[\u3010\u3011]', unicode: true), '')
        .replaceAll(RegExp(r'[\u3000]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _resolveSeriesName({
    required String rawSeries,
    required String filePath,
    String? releaseGroup,
  }) {
    final cleaned = _cleanSeriesName(rawSeries, releaseGroup: releaseGroup);
    if (cleaned.isNotEmpty && !_looksLikeOnlyReleaseGroup(rawSeries, cleaned)) {
      return cleaned;
    }

    final parentName = _seriesNameFromDirectory(filePath);
    return parentName.isEmpty ? cleaned : parentName;
  }

  String _cleanSeriesName(String value, {String? releaseGroup}) {
    var cleaned = value
        .replaceAll(
          RegExp(r'[\[\]\(\)\u300c\u300d\uff08\uff09]', unicode: true),
          ' ',
        )
        .replaceAll(RegExp(r'[\s._\-]+'), ' ')
        .trim();
    cleaned = _removeNoiseTokens(cleaned);
    cleaned = _removeLeadingReleaseGroup(cleaned, releaseGroup);
    return cleaned.trim();
  }

  String _cleanEpisodeTitle(String value) {
    var cleaned = _nameAnalyzer
        .cleanReleaseTokens(value)
        .replaceAll(
          RegExp(r'^[\s._\-\]\)\uff09:\uff1a]+', unicode: true),
          '',
        )
        .replaceAll(
          RegExp(r'[\[\]\(\)\u300c\u300d\uff08\uff09]', unicode: true),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    cleaned = _removeNoiseTokens(cleaned);
    return cleaned.trim();
  }

  String _removeNoiseTokens(String value) {
    final noise = RegExp(
      r'\b(480p|720p|1080p|1440p|2160p|4k|8k|x264|x265|h264|h265|hevc|avc|av1|aac|flac|web-dl|webrip|bdrip|bluray|bd|hdtv|tvrip|合集|简体|繁体|简繁|内封|外挂)\b',
      caseSensitive: false,
      unicode: true,
    );
    return value
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .where((part) => !noise.hasMatch(part))
        .join(' ');
  }

  String _removeLeadingReleaseGroup(String value, String? releaseGroup) {
    final group = releaseGroup?.trim();
    if (group == null || group.isEmpty) return value;
    return value
        .replaceFirst(
          RegExp(
            '^${RegExp.escape(group)}(?:\\s+|\$)',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String? _canonicalResolution(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == '4k' || lower == '8k') return lower.toUpperCase();
    return lower;
  }

  String? _canonicalSource(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    switch (text.toLowerCase()) {
      case 'web-dl':
        return 'Web-DL';
      case 'webrip':
        return 'WEBRip';
      case 'bdrip':
        return 'BDRip';
      case 'bluray':
        return 'BluRay';
      case 'bd':
        return 'BD';
      case 'tvrip':
        return 'TVRip';
      case 'hdtv':
        return 'HDTV';
    }
    return text;
  }

  String? _canonicalCodec(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text.toUpperCase();
  }

  bool _looksLikeOnlyReleaseGroup(String rawValue, String cleanedValue) {
    final raw = rawValue.trim();
    final parts =
        cleanedValue.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.length != 1) return false;
    if (!RegExp(r'^[\[\(\u300c\uff08].+[\]\)\u300d\uff09]$', unicode: true)
        .hasMatch(raw)) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9_ -]{2,24}$').hasMatch(parts.single);
  }

  int? _seasonFromDirectory(String filePath) {
    final parentName = p.basename(p.dirname(filePath));
    final match = RegExp(
      r'(?:season|s)\s*(\d{1,2})|\u7b2c\s*(\d{1,2})\s*[\u5b63\u90e8]',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(parentName);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? match.group(2) ?? '');
  }

  String _seriesNameFromDirectory(String filePath) {
    final parent = p.dirname(filePath);
    final parentName = p.basename(parent);
    if (_seasonFromDirectory(filePath) != null) {
      return _cleanSeriesName(p.basename(p.dirname(parent)));
    }
    return _cleanSeriesName(parentName);
  }
}
