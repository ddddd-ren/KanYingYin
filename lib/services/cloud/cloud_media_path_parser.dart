import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:path/path.dart' as p;

@immutable
class CloudMediaPathMatch {
  const CloudMediaPathMatch({
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.folderSeasonNumber,
    this.hasSeasonConflict = false,
  });

  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? folderSeasonNumber;
  final bool hasSeasonConflict;

  bool get isEpisode =>
      seriesName?.trim().isNotEmpty == true &&
      episodeNumber != null &&
      episodeNumber! > 0;
}

class CloudMediaPathParser {
  CloudMediaPathParser({LocalEpisodeParser? episodeParser})
      : _episodeParser = episodeParser ?? LocalEpisodeParser();

  static final RegExp _folderSeasonPattern = RegExp(
    r'^(.*?)(?:[\s._-]*第\s*([零〇一二两三四五六七八九十\d]{1,3})\s*季|[\s._-]*season\s*(\d{1,2})|[\s._-]*s(\d{1,2}))$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _fileSeasonPattern = RegExp(
    r'(?:\bS(\d{1,2})E\d{1,3}\b|第\s*(\d{1,2})\s*[季部]\s*第\s*\d{1,3}\s*[话話集])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _standaloneEpisodePattern = RegExp(
    r'^(?:ep?|第)?\s*(\d{1,3})\s*(?:集)?$',
    caseSensitive: false,
    unicode: true,
  );
  static const Set<String> _genericDirectoryNames = <String>{
    '电视剧',
    '剧集',
    'tv',
    'shows',
    'series',
    '动漫',
    'anime',
    '媒体',
    'media',
    '视频',
    'video',
    '网盘',
    '夸克网盘',
    '已整理',
  };

  final LocalEpisodeParser _episodeParser;

  CloudMediaPathMatch parse(String remotePath) {
    final normalizedPath = remotePath.trim().replaceAll('\\', '/');
    final fileName = p.posix.basenameWithoutExtension(normalizedPath);
    final parentName = p.posix.basename(p.posix.dirname(normalizedPath));
    final folder = _parseFolder(parentName, normalizedPath);
    final fileEpisode = _episodeParser.parse(normalizedPath);
    final fileSeasonNumber = _explicitFileSeason(fileName);
    final folderSeasonNumber = folder.$2;
    final hasSeasonConflict = fileSeasonNumber != null &&
        folderSeasonNumber != null &&
        fileSeasonNumber != folderSeasonNumber;
    final fileSeriesName = _usableSeriesName(fileEpisode?.seriesName);
    return CloudMediaPathMatch(
      seriesName: fileSeriesName ?? folder.$1,
      seasonNumber:
          fileSeasonNumber ?? folderSeasonNumber ?? fileEpisode?.seasonNumber,
      episodeNumber:
          fileEpisode?.episodeNumber ?? _parseStandaloneEpisode(fileName),
      folderSeasonNumber: folderSeasonNumber,
      hasSeasonConflict: hasSeasonConflict,
    );
  }

  (String?, int?) _parseFolder(String parentName, String remotePath) {
    final match = _folderSeasonPattern.firstMatch(parentName.trim());
    if (match == null) return (null, null);
    final season = _parseSeasonNumber(
      match.group(2) ?? match.group(3) ?? match.group(4) ?? '',
    );
    if (season == null) return (null, null);
    final inlineTitle = _usableSeriesName(match.group(1));
    if (inlineTitle != null) return (inlineTitle, season);
    final grandParent = p.posix.basename(
      p.posix.dirname(p.posix.dirname(remotePath)),
    );
    return (_usableSeriesName(grandParent), season);
  }

  int? _parseStandaloneEpisode(String value) {
    final match = _standaloneEpisodePattern.firstMatch(value.trim());
    final result = match == null ? null : int.tryParse(match.group(1)!);
    return result == null || result <= 0 ? null : result;
  }

  int? _explicitFileSeason(String fileName) {
    final match = _fileSeasonPattern.firstMatch(fileName);
    if (match == null) return null;
    return _parseSeasonNumber(match.group(1) ?? match.group(2) ?? '');
  }

  int? _parseSeasonNumber(String value) {
    final arabic = int.tryParse(value);
    if (arabic != null) {
      return arabic >= 1 && arabic <= 99 ? arabic : null;
    }
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

  String? _usableSeriesName(String? value) {
    final normalized = value
        ?.replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'[\s-]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (_genericDirectoryNames.contains(normalized.toLowerCase())) return null;
    return normalized;
  }
}
