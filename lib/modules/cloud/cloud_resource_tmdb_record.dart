import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

enum CloudResourceKind { directory, standaloneVideo }

enum CloudResourceTmdbStatus { unchecked, matched, unmatched, failed }

String cloudResourceTmdbKey({
  required String sourceId,
  required String remoteId,
  required String remotePath,
}) {
  var normalizedPath = remotePath.trim().replaceAll('\\', '/');
  normalizedPath = normalizedPath.replaceAll(RegExp(r'/+'), '/');
  if (normalizedPath.isEmpty) {
    normalizedPath = '/';
  } else if (!normalizedPath.startsWith('/')) {
    normalizedPath = '/$normalizedPath';
  }
  if (normalizedPath.length > 1 && normalizedPath.endsWith('/')) {
    normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
  }
  return '$sourceId|$remoteId|$normalizedPath';
}

class CloudResourceTmdbRecord {
  const CloudResourceTmdbRecord({
    required this.sourceId,
    required this.remoteId,
    required this.remotePath,
    required this.displayName,
    required this.resourceKind,
    required this.status,
    required this.checkedAt,
    this.tmdbId,
    this.mediaType,
    this.title,
    this.originalTitle,
    this.overview,
    this.rating,
    this.releaseDate,
    this.posterUrl,
    this.backdropUrl,
    this.posterCachePath,
    this.customTitle,
  });

  factory CloudResourceTmdbRecord.matched({
    required String sourceId,
    required String remoteId,
    required String remotePath,
    required String displayName,
    required CloudResourceKind resourceKind,
    required TmdbMetadata metadata,
    required DateTime checkedAt,
    String? posterCachePath,
    String? customTitle,
  }) {
    return CloudResourceTmdbRecord(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      displayName: displayName,
      resourceKind: resourceKind,
      status: CloudResourceTmdbStatus.matched,
      checkedAt: checkedAt,
      tmdbId: metadata.id,
      mediaType: metadata.mediaType,
      title: metadata.title,
      originalTitle: metadata.originalTitle,
      overview: metadata.overview,
      rating: metadata.rating,
      releaseDate: metadata.releaseDate,
      posterUrl: metadata.posterUrl,
      backdropUrl: metadata.backdropUrl,
      posterCachePath: posterCachePath,
      customTitle: customTitle,
    );
  }

  factory CloudResourceTmdbRecord.unmatched({
    required String sourceId,
    required String remoteId,
    required String remotePath,
    required String displayName,
    required CloudResourceKind resourceKind,
    required DateTime checkedAt,
    String? customTitle,
  }) {
    return CloudResourceTmdbRecord(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      displayName: displayName,
      resourceKind: resourceKind,
      status: CloudResourceTmdbStatus.unmatched,
      checkedAt: checkedAt,
      customTitle: customTitle,
    );
  }

  factory CloudResourceTmdbRecord.unchecked({
    required String sourceId,
    required String remoteId,
    required String remotePath,
    required String displayName,
    required CloudResourceKind resourceKind,
    required DateTime checkedAt,
    String? customTitle,
  }) {
    return CloudResourceTmdbRecord(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      displayName: displayName,
      resourceKind: resourceKind,
      status: CloudResourceTmdbStatus.unchecked,
      checkedAt: checkedAt,
      customTitle: customTitle,
    );
  }

  factory CloudResourceTmdbRecord.failed({
    required String sourceId,
    required String remoteId,
    required String remotePath,
    required String displayName,
    required CloudResourceKind resourceKind,
    required DateTime checkedAt,
    String? customTitle,
  }) {
    return CloudResourceTmdbRecord(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      displayName: displayName,
      resourceKind: resourceKind,
      status: CloudResourceTmdbStatus.failed,
      checkedAt: checkedAt,
      customTitle: customTitle,
    );
  }

  factory CloudResourceTmdbRecord.fromJson(Map<String, Object?> json) {
    return CloudResourceTmdbRecord(
      sourceId: json['sourceId'] as String? ?? '',
      remoteId: json['remoteId'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '/',
      displayName: json['displayName'] as String? ?? '',
      resourceKind: _enumValue(
        CloudResourceKind.values,
        json['resourceKind'],
        CloudResourceKind.directory,
      ),
      status: _enumValue(
        CloudResourceTmdbStatus.values,
        json['status'],
        CloudResourceTmdbStatus.unchecked,
      ),
      checkedAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(json['checkedAtMillis']),
        isUtc: true,
      ),
      tmdbId: _asNullableInt(json['tmdbId']),
      mediaType: json['mediaType'] == null
          ? null
          : _enumValue(
              TmdbMediaType.values,
              json['mediaType'],
              TmdbMediaType.tv,
            ),
      title: _asString(json['title']),
      originalTitle: _asString(json['originalTitle']),
      overview: _asString(json['overview']),
      rating: _asDouble(json['rating']),
      releaseDate: _asString(json['releaseDate']),
      posterUrl: _asString(json['posterUrl']),
      backdropUrl: _asString(json['backdropUrl']),
      posterCachePath: _asString(json['posterCachePath']),
      customTitle: _asString(json['customTitle']),
    );
  }

  final String sourceId;
  final String remoteId;
  final String remotePath;
  final String displayName;
  final CloudResourceKind resourceKind;
  final CloudResourceTmdbStatus status;
  final DateTime checkedAt;
  final int? tmdbId;
  final TmdbMediaType? mediaType;
  final String? title;
  final String? originalTitle;
  final String? overview;
  final double? rating;
  final String? releaseDate;
  final String? posterUrl;
  final String? backdropUrl;
  final String? posterCachePath;
  final String? customTitle;

  String get stableKey => cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: remoteId,
        remotePath: remotePath,
      );

  String get effectiveTitle {
    final custom = customTitle?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final matchedTitle = title?.trim();
    if (matchedTitle != null && matchedTitle.isNotEmpty) return matchedTitle;
    return displayName;
  }

  CloudResourceTmdbRecord withCustomTitle(String value) {
    final normalized = value.trim();
    return _copyWithCustomTitle(normalized.isEmpty ? null : normalized);
  }

  CloudResourceTmdbRecord clearCustomTitle() => _copyWithCustomTitle(null);

  CloudResourceTmdbRecord asFailed(DateTime checkedAt) {
    return CloudResourceTmdbRecord.failed(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      displayName: displayName,
      resourceKind: resourceKind,
      checkedAt: checkedAt,
      customTitle: customTitle,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sourceId': sourceId,
      'remoteId': remoteId,
      'remotePath': remotePath,
      'displayName': displayName,
      'resourceKind': resourceKind.name,
      'status': status.name,
      'checkedAtMillis': checkedAt.millisecondsSinceEpoch,
      if (tmdbId != null) 'tmdbId': tmdbId,
      if (mediaType != null) 'mediaType': mediaType!.name,
      if (title != null) 'title': title,
      if (originalTitle != null) 'originalTitle': originalTitle,
      if (overview != null) 'overview': overview,
      if (rating != null) 'rating': rating,
      if (releaseDate != null) 'releaseDate': releaseDate,
      if (posterUrl != null) 'posterUrl': posterUrl,
      if (backdropUrl != null) 'backdropUrl': backdropUrl,
      if (posterCachePath != null) 'posterCachePath': posterCachePath,
      if (customTitle != null) 'customTitle': customTitle,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CloudResourceTmdbRecord &&
            sourceId == other.sourceId &&
            remoteId == other.remoteId &&
            remotePath == other.remotePath &&
            displayName == other.displayName &&
            resourceKind == other.resourceKind &&
            status == other.status &&
            checkedAt == other.checkedAt &&
            tmdbId == other.tmdbId &&
            mediaType == other.mediaType &&
            title == other.title &&
            originalTitle == other.originalTitle &&
            overview == other.overview &&
            rating == other.rating &&
            releaseDate == other.releaseDate &&
            posterUrl == other.posterUrl &&
            backdropUrl == other.backdropUrl &&
            posterCachePath == other.posterCachePath &&
            customTitle == other.customTitle;
  }

  @override
  int get hashCode => Object.hash(
        sourceId,
        remoteId,
        remotePath,
        displayName,
        resourceKind,
        status,
        checkedAt,
        tmdbId,
        mediaType,
        title,
        originalTitle,
        overview,
        rating,
        releaseDate,
        posterUrl,
        backdropUrl,
        posterCachePath,
        customTitle,
      );

  CloudResourceTmdbRecord _copyWithCustomTitle(String? value) {
    return CloudResourceTmdbRecord(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      displayName: displayName,
      resourceKind: resourceKind,
      status: status,
      checkedAt: checkedAt,
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: title,
      originalTitle: originalTitle,
      overview: overview,
      rating: rating,
      releaseDate: releaseDate,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      posterCachePath: posterCachePath,
      customTitle: value,
    );
  }
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString();
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

int _asInt(Object? value) => _asNullableInt(value) ?? 0;

int? _asNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _asString(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}
