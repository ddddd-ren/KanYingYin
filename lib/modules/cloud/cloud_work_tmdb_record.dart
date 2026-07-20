import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

enum CloudWorkTmdbStatus { unchecked, matched, unmatched, failed, conflict }

@immutable
class CloudWorkTmdbRecord {
  const CloudWorkTmdbRecord({
    required this.sourceId,
    required this.workKey,
    required this.workRootId,
    required this.workRootPath,
    required this.remoteName,
    required this.status,
    required this.checkedAt,
    this.scrapeTitleOverride,
    this.metadata,
    this.posterCachePath,
  });

  factory CloudWorkTmdbRecord.matched({
    required String sourceId,
    required String workKey,
    required String workRootId,
    required String workRootPath,
    required String remoteName,
    required TmdbMetadata metadata,
    required DateTime checkedAt,
    String? scrapeTitleOverride,
    String? posterCachePath,
  }) {
    return CloudWorkTmdbRecord(
      sourceId: sourceId,
      workKey: workKey,
      workRootId: workRootId,
      workRootPath: workRootPath,
      remoteName: remoteName,
      status: CloudWorkTmdbStatus.matched,
      checkedAt: checkedAt,
      scrapeTitleOverride: _normalized(scrapeTitleOverride),
      metadata: metadata,
      posterCachePath: _normalized(posterCachePath),
    );
  }

  factory CloudWorkTmdbRecord.unchecked({
    required String sourceId,
    required String workKey,
    required String workRootId,
    required String workRootPath,
    required String remoteName,
    required DateTime checkedAt,
    String? scrapeTitleOverride,
  }) =>
      _withoutMetadata(
        sourceId: sourceId,
        workKey: workKey,
        workRootId: workRootId,
        workRootPath: workRootPath,
        remoteName: remoteName,
        status: CloudWorkTmdbStatus.unchecked,
        checkedAt: checkedAt,
        scrapeTitleOverride: scrapeTitleOverride,
      );

  factory CloudWorkTmdbRecord.unmatched({
    required String sourceId,
    required String workKey,
    required String workRootId,
    required String workRootPath,
    required String remoteName,
    required DateTime checkedAt,
    String? scrapeTitleOverride,
  }) =>
      _withoutMetadata(
        sourceId: sourceId,
        workKey: workKey,
        workRootId: workRootId,
        workRootPath: workRootPath,
        remoteName: remoteName,
        status: CloudWorkTmdbStatus.unmatched,
        checkedAt: checkedAt,
        scrapeTitleOverride: scrapeTitleOverride,
      );

  factory CloudWorkTmdbRecord.failed({
    required String sourceId,
    required String workKey,
    required String workRootId,
    required String workRootPath,
    required String remoteName,
    required DateTime checkedAt,
    String? scrapeTitleOverride,
  }) =>
      _withoutMetadata(
        sourceId: sourceId,
        workKey: workKey,
        workRootId: workRootId,
        workRootPath: workRootPath,
        remoteName: remoteName,
        status: CloudWorkTmdbStatus.failed,
        checkedAt: checkedAt,
        scrapeTitleOverride: scrapeTitleOverride,
      );

  factory CloudWorkTmdbRecord.conflict({
    required String sourceId,
    required String workKey,
    required String workRootId,
    required String workRootPath,
    required String remoteName,
    required DateTime checkedAt,
    String? scrapeTitleOverride,
  }) =>
      _withoutMetadata(
        sourceId: sourceId,
        workKey: workKey,
        workRootId: workRootId,
        workRootPath: workRootPath,
        remoteName: remoteName,
        status: CloudWorkTmdbStatus.conflict,
        checkedAt: checkedAt,
        scrapeTitleOverride: scrapeTitleOverride,
      );

  factory CloudWorkTmdbRecord.uncheckedFromWork(
    CloudWorkIdentity work, {
    required DateTime checkedAt,
  }) {
    return CloudWorkTmdbRecord.unchecked(
      sourceId: work.sourceId,
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      remoteName: work.remoteName,
      checkedAt: checkedAt,
    );
  }

  factory CloudWorkTmdbRecord.fromJson(Map<String, Object?> json) {
    final rawMetadata = json['metadata'];
    return CloudWorkTmdbRecord(
      sourceId: json['sourceId'] as String? ?? '',
      workKey: json['workKey'] as String? ?? '',
      workRootId: json['workRootId'] as String? ?? '',
      workRootPath: json['workRootPath'] as String? ?? '/',
      remoteName: json['remoteName'] as String? ?? '',
      status: CloudWorkTmdbStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => CloudWorkTmdbStatus.unchecked,
      ),
      checkedAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(json['checkedAtMillis']),
        isUtc: true,
      ),
      scrapeTitleOverride: _normalized(json['scrapeTitleOverride'] as String?),
      metadata: rawMetadata is Map
          ? TmdbMetadata.fromJson(Map<String, dynamic>.from(rawMetadata))
          : null,
      posterCachePath: _normalized(json['posterCachePath'] as String?),
    );
  }

  final String sourceId;
  final String workKey;
  final String workRootId;
  final String workRootPath;
  final String remoteName;
  final String? scrapeTitleOverride;
  final CloudWorkTmdbStatus status;
  final TmdbMetadata? metadata;
  final String? posterCachePath;
  final DateTime checkedAt;

  List<TmdbSeasonMetadata> get seasons =>
      metadata?.seasons ?? const <TmdbSeasonMetadata>[];

  String effectiveTitle(String recognizedTitle) {
    final tmdbTitle = metadata?.title.trim();
    if (status == CloudWorkTmdbStatus.matched &&
        tmdbTitle != null &&
        tmdbTitle.isNotEmpty) {
      return tmdbTitle;
    }
    final override = scrapeTitleOverride?.trim();
    return override == null || override.isEmpty ? recognizedTitle : override;
  }

  CloudWorkTmdbRecord copyWithScrapeTitle(String value) {
    return _copyWith(scrapeTitleOverride: _normalized(value));
  }

  CloudWorkTmdbRecord clearScrapeTitle() {
    return _copyWith(clearScrapeTitleOverride: true);
  }

  CloudWorkTmdbRecord withPosterCachePath(String? value) {
    final normalized = _normalized(value);
    return _copyWith(
      posterCachePath: normalized,
      clearPosterCachePath: normalized == null,
    );
  }

  CloudWorkTmdbRecord asFailed(DateTime value) {
    return CloudWorkTmdbRecord.failed(
      sourceId: sourceId,
      workKey: workKey,
      workRootId: workRootId,
      workRootPath: workRootPath,
      remoteName: remoteName,
      checkedAt: value,
      scrapeTitleOverride: scrapeTitleOverride,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'sourceId': sourceId,
        'workKey': workKey,
        'workRootId': workRootId,
        'workRootPath': workRootPath,
        'remoteName': remoteName,
        'status': status.name,
        'checkedAtMillis': checkedAt.millisecondsSinceEpoch,
        if (scrapeTitleOverride != null)
          'scrapeTitleOverride': scrapeTitleOverride,
        if (metadata != null) 'metadata': metadata!.toJson(),
        if (posterCachePath != null) 'posterCachePath': posterCachePath,
      };

  CloudWorkTmdbRecord _copyWith({
    String? scrapeTitleOverride,
    bool clearScrapeTitleOverride = false,
    String? posterCachePath,
    bool clearPosterCachePath = false,
  }) {
    return CloudWorkTmdbRecord(
      sourceId: sourceId,
      workKey: workKey,
      workRootId: workRootId,
      workRootPath: workRootPath,
      remoteName: remoteName,
      status: status,
      checkedAt: checkedAt,
      scrapeTitleOverride: clearScrapeTitleOverride
          ? null
          : scrapeTitleOverride ?? this.scrapeTitleOverride,
      metadata: metadata,
      posterCachePath:
          clearPosterCachePath ? null : posterCachePath ?? this.posterCachePath,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CloudWorkTmdbRecord &&
            sourceId == other.sourceId &&
            workKey == other.workKey &&
            workRootId == other.workRootId &&
            workRootPath == other.workRootPath &&
            remoteName == other.remoteName &&
            scrapeTitleOverride == other.scrapeTitleOverride &&
            status == other.status &&
            _metadataEquals(metadata, other.metadata) &&
            posterCachePath == other.posterCachePath &&
            checkedAt == other.checkedAt;
  }

  @override
  int get hashCode => Object.hash(
        sourceId,
        workKey,
        workRootId,
        workRootPath,
        remoteName,
        scrapeTitleOverride,
        status,
        _metadataHash(metadata),
        posterCachePath,
        checkedAt,
      );
}

CloudWorkTmdbRecord _withoutMetadata({
  required String sourceId,
  required String workKey,
  required String workRootId,
  required String workRootPath,
  required String remoteName,
  required CloudWorkTmdbStatus status,
  required DateTime checkedAt,
  String? scrapeTitleOverride,
}) {
  return CloudWorkTmdbRecord(
    sourceId: sourceId,
    workKey: workKey,
    workRootId: workRootId,
    workRootPath: workRootPath,
    remoteName: remoteName,
    status: status,
    checkedAt: checkedAt,
    scrapeTitleOverride: _normalized(scrapeTitleOverride),
  );
}

bool _metadataEquals(TmdbMetadata? first, TmdbMetadata? second) {
  if (identical(first, second)) return true;
  if (first == null || second == null) return false;
  return first.id == second.id &&
      first.mediaType == second.mediaType &&
      first.title == second.title &&
      first.originalTitle == second.originalTitle &&
      first.overview == second.overview &&
      first.releaseDate == second.releaseDate &&
      first.rating == second.rating &&
      first.posterUrl == second.posterUrl &&
      first.backdropUrl == second.backdropUrl &&
      first.language == second.language &&
      first.matchedAt.millisecondsSinceEpoch ==
          second.matchedAt.millisecondsSinceEpoch &&
      first.matchConfidence == second.matchConfidence &&
      listEquals(first.seasons, second.seasons);
}

int _metadataHash(TmdbMetadata? metadata) {
  if (metadata == null) return 0;
  return Object.hash(
    metadata.id,
    metadata.mediaType,
    metadata.title,
    metadata.originalTitle,
    metadata.overview,
    metadata.releaseDate,
    metadata.rating,
    metadata.posterUrl,
    metadata.backdropUrl,
    metadata.language,
    metadata.matchedAt.millisecondsSinceEpoch,
    metadata.matchConfidence,
    Object.hashAll(metadata.seasons),
  );
}

String? _normalized(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
