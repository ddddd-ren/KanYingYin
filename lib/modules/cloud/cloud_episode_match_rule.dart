import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';

enum CloudEpisodeMatchMode { mapped, keepOriginal }

String cloudEpisodeMatchRuleKey({
  required String sourceId,
  required String remoteId,
  required String remotePath,
}) {
  final path = CloudSeriesIdentityResolver.normalizeRemotePath(remotePath);
  return '${sourceId.trim()}|${remoteId.trim()}|$path';
}

final class CloudEpisodeMatchRule {
  const CloudEpisodeMatchRule._({
    required this.sourceId,
    required this.remoteId,
    required this.remotePath,
    required this.mode,
    required this.mediaType,
    required this.tmdbId,
    required this.updatedAt,
    this.seasonNumber,
    this.episodeNumber,
  });

  factory CloudEpisodeMatchRule.mapped({
    required String sourceId,
    required String remoteId,
    required String remotePath,
    required int tmdbId,
    required int seasonNumber,
    required int episodeNumber,
    required DateTime updatedAt,
    TmdbMediaType mediaType = TmdbMediaType.tv,
  }) {
    if (seasonNumber <= 0 || episodeNumber <= 0) {
      throw ArgumentError('网盘剧集映射的季号和集号必须为正整数');
    }
    return CloudEpisodeMatchRule._(
      sourceId: _requiredText(sourceId, '来源 ID'),
      remoteId: _requiredText(remoteId, '远程 ID'),
      remotePath: CloudSeriesIdentityResolver.normalizeRemotePath(remotePath),
      mode: CloudEpisodeMatchMode.mapped,
      mediaType: mediaType,
      tmdbId: _positiveTmdbId(tmdbId),
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      updatedAt: updatedAt.toUtc(),
    );
  }

  factory CloudEpisodeMatchRule.keepOriginal({
    required String sourceId,
    required String remoteId,
    required String remotePath,
    required int tmdbId,
    required DateTime updatedAt,
    TmdbMediaType mediaType = TmdbMediaType.tv,
  }) {
    return CloudEpisodeMatchRule._(
      sourceId: _requiredText(sourceId, '来源 ID'),
      remoteId: _requiredText(remoteId, '远程 ID'),
      remotePath: CloudSeriesIdentityResolver.normalizeRemotePath(remotePath),
      mode: CloudEpisodeMatchMode.keepOriginal,
      mediaType: mediaType,
      tmdbId: _positiveTmdbId(tmdbId),
      updatedAt: updatedAt.toUtc(),
    );
  }

  factory CloudEpisodeMatchRule.fromJson(Map<String, Object?> json) {
    final mode = CloudEpisodeMatchMode.values.firstWhere(
      (item) => item.name == json['mode'],
      orElse: () => throw const FormatException('无效的网盘剧集匹配模式'),
    );
    final mediaType = TmdbMediaType.values.firstWhere(
      (item) => item.name == json['mediaType'],
      orElse: () => throw const FormatException('无效的 TMDB 媒体类型'),
    );
    final tmdbId = _jsonInt(json['tmdbId']);
    final updatedAtMillis = _jsonInt(json['updatedAtMillis']);
    final seasonNumber = _nullableJsonInt(json['seasonNumber']);
    final episodeNumber = _nullableJsonInt(json['episodeNumber']);
    if (mode == CloudEpisodeMatchMode.mapped) {
      return CloudEpisodeMatchRule.mapped(
        sourceId: json['sourceId']?.toString() ?? '',
        remoteId: json['remoteId']?.toString() ?? '',
        remotePath: json['remotePath']?.toString() ?? '',
        mediaType: mediaType,
        tmdbId: tmdbId,
        seasonNumber: seasonNumber ?? 0,
        episodeNumber: episodeNumber ?? 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          updatedAtMillis,
          isUtc: true,
        ),
      );
    }
    return CloudEpisodeMatchRule.keepOriginal(
      sourceId: json['sourceId']?.toString() ?? '',
      remoteId: json['remoteId']?.toString() ?? '',
      remotePath: json['remotePath']?.toString() ?? '',
      mediaType: mediaType,
      tmdbId: tmdbId,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        updatedAtMillis,
        isUtc: true,
      ),
    );
  }

  final String sourceId;
  final String remoteId;
  final String remotePath;
  final CloudEpisodeMatchMode mode;
  final TmdbMediaType mediaType;
  final int tmdbId;
  final int? seasonNumber;
  final int? episodeNumber;
  final DateTime updatedAt;

  String get stableKey => cloudEpisodeMatchRuleKey(
        sourceId: sourceId,
        remoteId: remoteId,
        remotePath: remotePath,
      );

  bool matches({
    required String sourceId,
    required String remoteId,
    required String remotePath,
  }) {
    return stableKey ==
        cloudEpisodeMatchRuleKey(
          sourceId: sourceId,
          remoteId: remoteId,
          remotePath: remotePath,
        );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'sourceId': sourceId,
        'remoteId': remoteId,
        'remotePath': remotePath,
        'mode': mode.name,
        'mediaType': mediaType.name,
        'tmdbId': tmdbId,
        if (seasonNumber != null) 'seasonNumber': seasonNumber,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
        'updatedAtMillis': updatedAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) {
    return other is CloudEpisodeMatchRule &&
        other.sourceId == sourceId &&
        other.remoteId == remoteId &&
        other.remotePath == remotePath &&
        other.mode == mode &&
        other.mediaType == mediaType &&
        other.tmdbId == tmdbId &&
        other.seasonNumber == seasonNumber &&
        other.episodeNumber == episodeNumber &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        sourceId,
        remoteId,
        remotePath,
        mode,
        mediaType,
        tmdbId,
        seasonNumber,
        episodeNumber,
        updatedAt,
      );
}

String _requiredText(String value, String fieldName) {
  final text = value.trim();
  if (text.isEmpty) throw FormatException('$fieldName 不能为空');
  return text;
}

int _positiveTmdbId(int value) {
  if (value <= 0) throw const FormatException('TMDB ID 必须为正整数');
  return value;
}

int _jsonInt(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableJsonInt(Object? value) {
  if (value == null) return null;
  final parsed = _jsonInt(value);
  return parsed > 0 ? parsed : null;
}
