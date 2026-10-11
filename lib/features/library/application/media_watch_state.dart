import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/utils/user_data_mutation_lock.dart';
import 'package:path/path.dart' as p;

String mediaWatchKey({String? localPath, String? sourceId, String? remoteId}) {
  if (localPath != null) {
    final windows = RegExp(r'^[a-zA-Z]:[\\/]|^\\\\').hasMatch(localPath);
    final path = p.Context(style: windows ? p.Style.windows : p.Style.posix)
        .normalize(localPath);
    return 'local|${windows ? path.toLowerCase() : path}';
  }
  return '$sourceId|$remoteId';
}

String mediaWatchKeyForEpisode(MediaLibraryEpisode episode) =>
    episode.sourceKind == MediaSourceKind.local
        ? mediaWatchKey(localPath: episode.localItem?.path ?? episode.stableId)
        : mediaWatchKey(sourceId: episode.sourceId, remoteId: episode.remoteId);

class MediaWatchState {
  const MediaWatchState(
      {required this.watched,
      required this.position,
      required this.duration,
      required this.updatedAt});
  final bool watched;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  double get progress => watched
      ? 1
      : duration > Duration.zero
          ? (position.inMilliseconds / duration.inMilliseconds)
              .clamp(0, 1)
              .toDouble()
          : 0;
  Map<String, Object> toJson() => {
        'watched': watched,
        'positionMillis': position.inMilliseconds,
        'durationMillis': duration.inMilliseconds,
        'updatedAtMillis': updatedAt.millisecondsSinceEpoch,
      };
  factory MediaWatchState.fromJson(Map<Object?, Object?> json) {
    final position = json['positionMillis'];
    final duration = json['durationMillis'];
    final updated = json['updatedAtMillis'];
    if (json['watched'] is! bool ||
        position is! int ||
        duration is! int ||
        updated is! int ||
        position < 0 ||
        duration < 0 ||
        position > duration ||
        duration > 2147483647 ||
        updated < 0 ||
        updated > 8640000000000000) {
      throw const FormatException('已看记录无效');
    }
    return MediaWatchState(
        watched: json['watched'] as bool,
        position: Duration(milliseconds: position),
        duration: Duration(milliseconds: duration),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updated));
  }
}

class MediaWatchStateRepository {
  MediaWatchStateRepository(this.storage);
  final PlayerBookmarkStorage storage;
  static final ValueNotifier<int> changes = ValueNotifier(0);
  Map<String, MediaWatchState> loadAll() {
    final raw = storage.read();
    final result = <String, MediaWatchState>{};
    if (raw is! Map) return result;
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      try {
        result[entry.key as String] = MediaWatchState.fromJson(
            Map<Object?, Object?>.from(entry.value as Map));
      } on Object {/* 单条损坏不影响其他媒体。 */}
    }
    return result;
  }

  Future<void> record(String key,
          {required Duration position,
          required Duration duration,
          required bool completed}) =>
      userDataMutationLock.synchronized(() async {
        if (key.isEmpty ||
            duration <= Duration.zero ||
            duration.inMilliseconds > 2147483647) {
          return;
        }
        final states = loadAll();
        final old = states[key];
        final safePosition = completed
            ? duration
            : Duration(
                milliseconds:
                    position.inMilliseconds.clamp(0, duration.inMilliseconds));
        final watched = completed || (old?.watched ?? false);
        if (old != null &&
            old.watched == watched &&
            old.duration == duration &&
            (old.position - safePosition).abs() < const Duration(seconds: 10)) {
          return;
        }
        states[key] = MediaWatchState(
            watched: watched,
            position: safePosition,
            duration: duration,
            updatedAt: DateTime.now());
        await _write(states);
      });
  Future<void> setWatched(Iterable<String> keys, bool watched) =>
      userDataMutationLock.synchronized(() async {
        final states = loadAll();
        for (final key in keys) {
          if (key.isEmpty) throw const FormatException('媒体身份无效');
          final duration = states[key]?.duration ?? Duration.zero;
          states[key] = MediaWatchState(
              watched: watched,
              position: watched ? duration : Duration.zero,
              duration: duration,
              updatedAt: DateTime.now());
        }
        await _write(states);
      });
  Future<void> _write(Map<String, MediaWatchState> states) async {
    await storage.write(
        {for (final entry in states.entries) entry.key: entry.value.toJson()});
    changes.value++;
  }
}

bool mediaSeriesWatched(
        MediaLibrarySeries series, Map<String, MediaWatchState> states) =>
    series.episodes.isNotEmpty &&
    series.episodes.every(
        (episode) => states[mediaWatchKeyForEpisode(episode)]?.watched == true);

double mediaSeriesProgress(
        MediaLibrarySeries series, Map<String, MediaWatchState> states) =>
    series.episodes.isEmpty
        ? 0
        : series.episodes.fold<double>(
                0,
                (sum, episode) =>
                    sum +
                    (states[mediaWatchKeyForEpisode(episode)]?.progress ?? 0)) /
            series.episodes.length;
