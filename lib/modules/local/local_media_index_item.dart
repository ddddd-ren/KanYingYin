import 'dart:io';

import 'package:kanyingyin/modules/local/local_episode_info.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:path/path.dart' as p;

class LocalMediaIndexItem {
  static const int pathFingerprintVersion = 2;
  static const int currentDerivedMetadataVersion = 3;

  final String path;
  final String name;
  final String parentPath;
  final String sourcePath;
  final int size;
  final DateTime modified;
  final String? cover;
  final String? subtitlePath;
  final int? durationMillis;
  final int? videoWidth;
  final int? videoHeight;
  final String seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final String? releaseGroup;
  final String? resolution;
  final String? source;
  final String? codec;
  final TmdbMetadata? tmdb;
  final bool titleLocked;
  final bool posterLocked;
  final bool overviewLocked;
  final TmdbScrapeStatus scrapeStatus;
  final TmdbMatchOrigin tmdbMatchOrigin;
  final int tmdbRuleVersion;
  final bool manualOverride;
  final String pathFingerprint;
  final int derivedMetadataVersion;
  final DateTime indexedAt;

  const LocalMediaIndexItem({
    required this.path,
    required this.name,
    required this.parentPath,
    required this.sourcePath,
    required this.size,
    required this.modified,
    required this.seriesName,
    required this.indexedAt,
    this.cover,
    this.subtitlePath,
    this.durationMillis,
    this.videoWidth,
    this.videoHeight,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.releaseGroup,
    this.resolution,
    this.source,
    this.codec,
    this.tmdb,
    this.titleLocked = false,
    this.posterLocked = false,
    this.overviewLocked = false,
    this.scrapeStatus = TmdbScrapeStatus.none,
    this.tmdbMatchOrigin = TmdbMatchOrigin.legacyUnknown,
    this.tmdbRuleVersion = 0,
    this.manualOverride = false,
    String? pathFingerprint,
    this.derivedMetadataVersion = currentDerivedMetadataVersion,
  }) : pathFingerprint = pathFingerprint ?? '';

  factory LocalMediaIndexItem.fromFile({
    required File file,
    required FileStat stat,
    required String sourcePath,
    String? cover,
    String? subtitlePath,
    LocalEpisodeInfo? episodeInfo,
    Duration? duration,
    int? videoWidth,
    int? videoHeight,
    DateTime? indexedAt,
  }) {
    final fileName = p.basename(file.path);
    return LocalMediaIndexItem(
      path: file.path,
      name: fileName,
      parentPath: p.dirname(file.path),
      sourcePath: sourcePath,
      size: stat.size,
      modified: stat.modified,
      cover: cover,
      subtitlePath: subtitlePath,
      durationMillis: duration?.inMilliseconds,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      seriesName: episodeInfo?.seriesName ?? p.basename(p.dirname(file.path)),
      seasonNumber: episodeInfo?.seasonNumber,
      episodeNumber: episodeInfo?.episodeNumber,
      episodeTitle: episodeInfo?.episodeTitle,
      releaseGroup: episodeInfo?.releaseGroup,
      resolution: episodeInfo?.resolution,
      source: episodeInfo?.source,
      codec: episodeInfo?.codec,
      manualOverride: false,
      pathFingerprint: buildPathFingerprint(file.path, stat),
      derivedMetadataVersion: currentDerivedMetadataVersion,
      indexedAt: indexedAt ?? DateTime.now(),
    );
  }

  factory LocalMediaIndexItem.fromJson(Map<String, dynamic> json) {
    return LocalMediaIndexItem(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      parentPath: json['parentPath'] as String? ?? '',
      sourcePath: json['sourcePath'] as String? ?? '',
      size: _asInt(json['size']),
      modified: _dateFromMillis(json['modifiedMillis']),
      cover: _asNullableString(json['cover']),
      subtitlePath: _asNullableString(json['subtitlePath']),
      durationMillis: _asNullableInt(json['durationMillis']),
      videoWidth: _asNullableInt(json['videoWidth']),
      videoHeight: _asNullableInt(json['videoHeight']),
      seriesName: json['seriesName'] as String? ?? '',
      seasonNumber: _asNullableInt(json['seasonNumber']),
      episodeNumber: _asNullableInt(json['episodeNumber']),
      episodeTitle: _asNullableString(json['episodeTitle']),
      releaseGroup: _asNullableString(json['releaseGroup']),
      resolution: _asNullableString(json['resolution']),
      source: _asNullableString(json['source']),
      codec: _asNullableString(json['codec']),
      tmdb: _parseTmdb(json),
      titleLocked: json['titleLocked'] == true,
      posterLocked: json['posterLocked'] == true,
      overviewLocked: json['overviewLocked'] == true,
      scrapeStatus: _parseScrapeStatus(json['scrapeStatus']),
      tmdbMatchOrigin: _parseTmdbMatchOrigin(json['tmdbMatchOrigin']),
      tmdbRuleVersion: _asInt(json['tmdbRuleVersion']),
      manualOverride: json['manualOverride'] == true,
      pathFingerprint: _asNullableString(json['pathFingerprint']) ??
          _fallbackFingerprint(
            json['path'] as String? ?? '',
            _asInt(json['size']),
            _dateFromMillis(json['modifiedMillis']),
          ),
      derivedMetadataVersion:
          _asInt(json['derivedMetadataVersion'] ?? json['metadataVersion']),
      indexedAt: _dateFromMillis(json['indexedAtMillis']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'name': name,
      'parentPath': parentPath,
      'sourcePath': sourcePath,
      'size': size,
      'modifiedMillis': modified.millisecondsSinceEpoch,
      if (cover != null && cover!.isNotEmpty) 'cover': cover,
      if (subtitlePath != null && subtitlePath!.isNotEmpty)
        'subtitlePath': subtitlePath,
      if (durationMillis != null) 'durationMillis': durationMillis,
      if (videoWidth != null) 'videoWidth': videoWidth,
      if (videoHeight != null) 'videoHeight': videoHeight,
      'seriesName': seriesName,
      if (seasonNumber != null) 'seasonNumber': seasonNumber,
      if (episodeNumber != null) 'episodeNumber': episodeNumber,
      if (episodeTitle != null && episodeTitle!.isNotEmpty)
        'episodeTitle': episodeTitle,
      if (releaseGroup != null && releaseGroup!.isNotEmpty)
        'releaseGroup': releaseGroup,
      if (resolution != null && resolution!.isNotEmpty)
        'resolution': resolution,
      if (source != null && source!.isNotEmpty) 'source': source,
      if (codec != null && codec!.isNotEmpty) 'codec': codec,
      if (tmdb != null) 'tmdb': tmdb!.toJson(),
      if (titleLocked) 'titleLocked': true,
      if (posterLocked) 'posterLocked': true,
      if (overviewLocked) 'overviewLocked': true,
      if (scrapeStatus != TmdbScrapeStatus.none)
        'scrapeStatus': scrapeStatus.name,
      if (tmdbMatchOrigin != TmdbMatchOrigin.legacyUnknown)
        'tmdbMatchOrigin': tmdbMatchOrigin.name,
      if (tmdbRuleVersion > 0) 'tmdbRuleVersion': tmdbRuleVersion,
      if (manualOverride) 'manualOverride': manualOverride,
      'pathFingerprint': pathFingerprint,
      'derivedMetadataVersion': derivedMetadataVersion,
      'indexedAtMillis': indexedAt.millisecondsSinceEpoch,
    };
  }

  String get id => normalizePath(path);

  bool get hasCurrentDerivedMetadata =>
      derivedMetadataVersion >= currentDerivedMetadataVersion;

  String get displayTitle {
    final info = episodeInfo;
    if (info != null) return info.displayTitle;
    return name;
  }

  String get seriesKey {
    final normalizedSeries =
        seriesName.trim().isEmpty ? p.basename(parentPath) : seriesName.trim();
    final season = seasonNumber;
    if (season != null && season > 0) {
      return '$normalizedSeries#S$season';
    }
    return normalizedSeries;
  }

  LocalEpisodeInfo? get episodeInfo {
    final episode = episodeNumber;
    if (episode == null || episode <= 0) return null;
    return LocalEpisodeInfo(
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episode,
      episodeTitle: episodeTitle,
      releaseGroup: releaseGroup,
      resolution: resolution,
      source: source,
      codec: codec,
    );
  }

  bool isSameFile(FileStat stat) {
    return size == stat.size &&
        modified.millisecondsSinceEpoch ==
            stat.modified.millisecondsSinceEpoch &&
        pathFingerprint == buildPathFingerprint(path, stat);
  }

  LocalFileItem toFileItem() {
    return LocalFileItem(
      path: path,
      name: name,
      size: size,
      modified: modified,
      isDirectory: false,
      isVideo: true,
      cover: cover,
      subtitlePath: subtitlePath,
      duration: durationMillis == null
          ? null
          : Duration(milliseconds: durationMillis!),
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      episodeInfo: episodeInfo,
      releaseGroup: releaseGroup,
      resolution: resolution,
      source: source,
      codec: codec,
    );
  }

  LocalMediaIndexItem copyWith({
    String? path,
    String? name,
    String? parentPath,
    String? sourcePath,
    int? size,
    DateTime? modified,
    String? cover,
    String? subtitlePath,
    int? durationMillis,
    int? videoWidth,
    int? videoHeight,
    String? seriesName,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    String? releaseGroup,
    String? resolution,
    String? source,
    String? codec,
    TmdbMetadata? tmdb,
    bool? titleLocked,
    bool? posterLocked,
    bool? overviewLocked,
    TmdbScrapeStatus? scrapeStatus,
    TmdbMatchOrigin? tmdbMatchOrigin,
    int? tmdbRuleVersion,
    bool? manualOverride,
    String? pathFingerprint,
    int? derivedMetadataVersion,
    DateTime? indexedAt,
  }) {
    return LocalMediaIndexItem(
      path: path ?? this.path,
      name: name ?? this.name,
      parentPath: parentPath ?? this.parentPath,
      sourcePath: sourcePath ?? this.sourcePath,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      cover: cover ?? this.cover,
      subtitlePath: subtitlePath ?? this.subtitlePath,
      durationMillis: durationMillis ?? this.durationMillis,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      seriesName: seriesName ?? this.seriesName,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      releaseGroup: releaseGroup ?? this.releaseGroup,
      resolution: resolution ?? this.resolution,
      source: source ?? this.source,
      codec: codec ?? this.codec,
      tmdb: tmdb ?? this.tmdb,
      titleLocked: titleLocked ?? this.titleLocked,
      posterLocked: posterLocked ?? this.posterLocked,
      overviewLocked: overviewLocked ?? this.overviewLocked,
      scrapeStatus: scrapeStatus ?? this.scrapeStatus,
      tmdbMatchOrigin: tmdbMatchOrigin ?? this.tmdbMatchOrigin,
      tmdbRuleVersion: tmdbRuleVersion ?? this.tmdbRuleVersion,
      manualOverride: manualOverride ?? this.manualOverride,
      pathFingerprint: pathFingerprint ?? this.pathFingerprint,
      derivedMetadataVersion:
          derivedMetadataVersion ?? this.derivedMetadataVersion,
      indexedAt: indexedAt ?? this.indexedAt,
    );
  }

  static String normalizePath(String path) {
    return p.normalize(path).toLowerCase();
  }

  static String buildPathFingerprint(String path, FileStat stat) {
    return _fallbackFingerprint(path, stat.size, stat.modified);
  }

  static String _fallbackFingerprint(String path, int size, DateTime modified) {
    return 'v$pathFingerprintVersion|${normalizePath(path)}|$size|${modified.millisecondsSinceEpoch}';
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static String? _asNullableString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime _dateFromMillis(Object? value) {
    final millis = _asInt(value);
    if (millis <= 0) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static TmdbMetadata? _parseTmdb(Map<String, dynamic> json) {
    final rawTmdb = json['tmdb'];
    if (rawTmdb is Map) {
      try {
        return TmdbMetadata.fromJson(Map<String, dynamic>.from(rawTmdb));
      } on Object {
        return null;
      }
    }
    return null;
  }

  static TmdbScrapeStatus _parseScrapeStatus(Object? value) {
    return TmdbScrapeStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TmdbScrapeStatus.none,
    );
  }

  static TmdbMatchOrigin _parseTmdbMatchOrigin(Object? value) {
    return TmdbMatchOrigin.values.firstWhere(
      (origin) => origin.name == value,
      orElse: () => TmdbMatchOrigin.legacyUnknown,
    );
  }
}
