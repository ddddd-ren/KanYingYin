import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';

String cloudSeriesMatchRuleKey({
  required String sourceId,
  required String parentPath,
  required String normalizedSeriesName,
}) {
  final path = CloudSeriesIdentityResolver.normalizeRemotePath(parentPath);
  final series = CloudSeriesIdentityResolver.normalizeSeriesName(
    normalizedSeriesName,
  );
  return '${sourceId.trim()}|$path|$series';
}

class CloudSeriesMatchRule {
  const CloudSeriesMatchRule({
    required this.sourceId,
    required this.parentPath,
    required this.normalizedSeriesName,
    required this.metadata,
    required this.updatedAt,
    this.posterCachePath,
  });

  factory CloudSeriesMatchRule.fromJson(Map<String, Object?> json) {
    final sourceId = json['sourceId'];
    final parentPath = json['parentPath'];
    final normalizedSeriesName = json['normalizedSeriesName'];
    final metadata = json['metadata'];
    final updatedAtMillis = json['updatedAtMillis'];
    if (sourceId is! String ||
        sourceId.trim().isEmpty ||
        parentPath is! String ||
        normalizedSeriesName is! String ||
        normalizedSeriesName.trim().isEmpty ||
        metadata is! Map ||
        updatedAtMillis is! num) {
      throw const FormatException('无效的网盘系列匹配规则');
    }
    final parsedMetadata = TmdbMetadata.fromJson(
      Map<String, dynamic>.from(metadata),
    );
    if (parsedMetadata.id <= 0 || parsedMetadata.title.trim().isEmpty) {
      throw const FormatException('无效的 TMDB 系列元数据');
    }
    return CloudSeriesMatchRule(
      sourceId: sourceId.trim(),
      parentPath: CloudSeriesIdentityResolver.normalizeRemotePath(parentPath),
      normalizedSeriesName: CloudSeriesIdentityResolver.normalizeSeriesName(
        normalizedSeriesName,
      ),
      metadata: parsedMetadata,
      posterCachePath: _stringOrNull(json['posterCachePath']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        updatedAtMillis.toInt(),
        isUtc: true,
      ),
    );
  }

  final String sourceId;
  final String parentPath;
  final String normalizedSeriesName;
  final TmdbMetadata metadata;
  final String? posterCachePath;
  final DateTime updatedAt;

  String get stableKey => cloudSeriesMatchRuleKey(
        sourceId: sourceId,
        parentPath: parentPath,
        normalizedSeriesName: normalizedSeriesName,
      );

  CloudSeriesMatchRule copyWith({DateTime? updatedAt}) {
    return CloudSeriesMatchRule(
      sourceId: sourceId,
      parentPath: parentPath,
      normalizedSeriesName: normalizedSeriesName,
      metadata: metadata,
      posterCachePath: posterCachePath,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'sourceId': sourceId,
        'parentPath': parentPath,
        'normalizedSeriesName': normalizedSeriesName,
        'metadata': metadata.toJson(),
        if (posterCachePath != null) 'posterCachePath': posterCachePath,
        'updatedAtMillis': updatedAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CloudSeriesMatchRule &&
            sourceId == other.sourceId &&
            parentPath == other.parentPath &&
            normalizedSeriesName == other.normalizedSeriesName &&
            _metadataEquals(metadata, other.metadata) &&
            posterCachePath == other.posterCachePath &&
            updatedAt.millisecondsSinceEpoch ==
                other.updatedAt.millisecondsSinceEpoch;
  }

  @override
  int get hashCode => Object.hash(
        sourceId,
        parentPath,
        normalizedSeriesName,
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
        posterCachePath,
        updatedAt.millisecondsSinceEpoch,
      );
}

bool _metadataEquals(TmdbMetadata first, TmdbMetadata second) {
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
      _seasonListsEqual(first.seasons, second.seasons);
}

bool _seasonListsEqual(
  List<TmdbSeasonMetadata> first,
  List<TmdbSeasonMetadata> second,
) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
