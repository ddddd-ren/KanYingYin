import 'package:path/path.dart' as p;

/// 观看历史的媒体来源。
enum PlaybackHistorySource { local, cloud }

/// 一条可恢复播放的历史记录。
class PlaybackHistoryEntry {
  const PlaybackHistoryEntry({
    required this.stableKey,
    required this.source,
    required this.sourceId,
    required this.seriesTitle,
    required this.episodeTitle,
    required this.mediaPath,
    required this.episodeIndex,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
    this.remoteId,
    this.posterUrl,
    this.posterCachePath,
  });

  final String stableKey;
  final PlaybackHistorySource source;
  final String sourceId;
  final String seriesTitle;
  final String episodeTitle;

  /// 本地文件路径，或网盘远程路径。
  final String mediaPath;
  final String? remoteId;
  final int episodeIndex;
  final int positionSeconds;
  final int durationSeconds;
  final DateTime updatedAt;
  final String? posterUrl;
  final String? posterCachePath;

  bool get isCloud => source == PlaybackHistorySource.cloud;

  bool get isCompleted =>
      durationSeconds > 0 && positionSeconds >= durationSeconds - 5;

  Duration get position => Duration(seconds: positionSeconds);

  Duration get duration => Duration(seconds: durationSeconds);

  /// 完播记录再次打开时从头播放，避免恢复到视频末尾。
  Duration get resumePosition => isCompleted ? Duration.zero : position;

  String get displayTitle {
    final series = seriesTitle.trim();
    final episode = episodeTitle.trim();
    if (series.isEmpty) {
      return episode.isEmpty ? p.basename(mediaPath) : episode;
    }
    if (episode.isEmpty || episode == series) return series;
    return '$series · $episode';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'stableKey': stableKey,
        'source': source.name,
        'sourceId': sourceId,
        'seriesTitle': seriesTitle,
        'episodeTitle': episodeTitle,
        'mediaPath': mediaPath,
        if (remoteId != null) 'remoteId': remoteId,
        'episodeIndex': episodeIndex,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'updatedAtMillis': updatedAt.millisecondsSinceEpoch,
        if (posterUrl != null) 'posterUrl': posterUrl,
        if (posterCachePath != null) 'posterCachePath': posterCachePath,
      };

  factory PlaybackHistoryEntry.fromJson(Map<Object?, Object?> json) {
    final stableKey = _string(json['stableKey']);
    final source = PlaybackHistorySource.values.firstWhere(
      (value) => value.name == json['source'],
      orElse: () => PlaybackHistorySource.local,
    );
    final sourceId = _string(json['sourceId']);
    final mediaPath = _string(json['mediaPath']);
    if (stableKey.isEmpty || sourceId.isEmpty || mediaPath.isEmpty) {
      throw const FormatException('观看历史缺少稳定标识或媒体路径');
    }
    final updatedMillis = _int(json['updatedAtMillis']);
    return PlaybackHistoryEntry(
      stableKey: stableKey,
      source: source,
      sourceId: sourceId,
      seriesTitle: _string(json['seriesTitle']),
      episodeTitle: _string(json['episodeTitle']),
      mediaPath: mediaPath,
      remoteId: _nullableString(json['remoteId']),
      episodeIndex: _boundedInt(_int(json['episodeIndex'], fallback: 1), 1),
      positionSeconds: _boundedInt(_int(json['positionSeconds']), 0),
      durationSeconds: _boundedInt(_int(json['durationSeconds']), 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        updatedMillis > 0 ? updatedMillis : 0,
        isUtc: true,
      ).toLocal(),
      posterUrl: _nullableString(json['posterUrl']),
      posterCachePath: _nullableString(json['posterCachePath']),
    );
  }

  PlaybackHistoryEntry copyWith({
    int? positionSeconds,
    int? durationSeconds,
    DateTime? updatedAt,
  }) {
    return PlaybackHistoryEntry(
      stableKey: stableKey,
      source: source,
      sourceId: sourceId,
      seriesTitle: seriesTitle,
      episodeTitle: episodeTitle,
      mediaPath: mediaPath,
      remoteId: remoteId,
      episodeIndex: episodeIndex,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
      posterUrl: posterUrl,
      posterCachePath: posterCachePath,
    );
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static String? _nullableString(Object? value) {
    final normalized = _string(value);
    return normalized.isEmpty ? null : normalized;
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int _boundedInt(int value, int lower) {
    if (value < lower) return lower;
    if (value > 2147483647) return 2147483647;
    return value;
  }
}
