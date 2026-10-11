import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/features/player/application/player_timeline_segments.dart';
import 'package:kanyingyin/features/player/application/track_selection_preferences.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:path/path.dart' as p;

/// 只迁移用户标记，不包含媒体索引、缓存或原始文件。
class PortableUserData {
  const PortableUserData({
    this.states = const {},
    this.bookmarks = const {},
    this.history = const [],
    this.localRoots = const [],
    this.timelineSegments = const {},
    this.watchStates = const {},
    this.trackPreferences = const {},
    this.preferredAudioLanguage,
    this.preferredSubtitleLanguage,
    this.classificationMode,
  });

  final Map<String, MediaLibraryUserState> states;
  final Map<String, List<PlayerBookmark>> bookmarks;
  final List<PlaybackHistoryEntry> history;
  final List<String> localRoots;
  final Map<String, PlayerTimelineSegmentRecord> timelineSegments;
  final Map<String, MediaWatchState> watchStates;
  final Map<String, Map<String, TrackLanguageChoice>> trackPreferences;
  final String? preferredAudioLanguage;
  final String? preferredSubtitleLanguage;
  final String? classificationMode;

  factory PortableUserData.fromJson(Map<String, Object?> json) {
    Map<String, Object?> readMap(String field) {
      final value = json[field] ?? <String, Object?>{};
      if (value is! Map ||
          value.length > 10000 ||
          value.keys.any(
              (key) => key is! String || key.isEmpty || key.length > 4096)) {
        throw const FormatException('用户数据集合无效');
      }
      return Map<String, Object?>.from(value);
    }

    final states = <String, MediaLibraryUserState>{};
    for (final entry in readMap('states').entries) {
      if (entry.value is! Map) throw const FormatException('作品状态无效');
      final raw = Map<Object?, Object?>.from(entry.value as Map);
      final ids = raw['mediaIds'];
      if (ids != null &&
          (ids is! List ||
              ids.length > 10000 ||
              ids.any((id) => id is! String || id.length > 4096))) {
        throw const FormatException('媒体成员无效');
      }
      states[entry.key] = MediaLibraryUserState.fromJson(raw);
    }
    final bookmarks = <String, List<PlayerBookmark>>{};
    for (final entry in readMap('bookmarks').entries) {
      final values = entry.value;
      if (values is! List ||
          values.length > PlayerBookmarkRepository.maxBookmarksPerMedia) {
        throw const FormatException('书签集合无效');
      }
      bookmarks[entry.key] = List.unmodifiable(values.map((value) {
        if (value is! Map ||
            value['positionMillis'] is! int ||
            (value['positionMillis'] as int) < 0 ||
            (value['positionMillis'] as int) > 2147483647) {
          throw const FormatException('书签位置无效');
        }
        return PlayerBookmark.fromJson(Map<Object?, Object?>.from(value));
      }));
    }
    final history = json['history'] ?? <Object?>[];
    Map<String, T> readRecords<T>(
            String field, T Function(Map<Object?, Object?>) parse) =>
        {
          for (final entry in readMap(field).entries)
            entry.key: entry.value is Map
                ? parse(Map<Object?, Object?>.from(entry.value as Map))
                : throw const FormatException('用户记录无效'),
        };
    final segments =
        readRecords('timelineSegments', PlayerTimelineSegmentRecord.fromJson);
    final watchStates = readRecords('watchStates', MediaWatchState.fromJson);
    final preferences = readRecords('trackPreferences', (raw) {
      if (raw.length > 2 ||
          raw.keys.any((key) => key != 'audio' && key != 'subtitle')) {
        throw const FormatException('作品选轨偏好无效');
      }
      return <String, TrackLanguageChoice>{
        for (final entry in raw.entries)
          entry.key as String: entry.value is Map
              ? parseTrackPreference(
                  Map<Object?, Object?>.from(entry.value as Map))
              : throw const FormatException('选轨偏好无效')
      };
    });
    String? readLanguage(String field, EmbeddedTrackType type) {
      final raw = json[field];
      if (raw == null) return null;
      if (raw is! String ||
          (raw != 'auto' && globalTrackPreference(raw, type) == null)) {
        throw const FormatException('全局选轨偏好无效');
      }
      return raw;
    }

    final classificationMode = json['classificationMode'];
    if (classificationMode != null &&
        !const {'conservative', 'standard', 'manual'}
            .contains(classificationMode)) {
      throw const FormatException('分类模式无效');
    }
    final roots = json['localRoots'] ?? <Object?>[];
    if (history is! List ||
        history.length > 100 ||
        roots is! List ||
        roots.length > 50 ||
        roots.any(
            (root) => root is! String || root.isEmpty || root.length > 4096)) {
      throw const FormatException('历史或目录集合无效');
    }
    return PortableUserData(
      states: Map.unmodifiable(states),
      bookmarks: Map.unmodifiable(bookmarks),
      history: List.unmodifiable(history.map((value) {
        if (value is! Map) throw const FormatException('观看历史无效');
        return PlaybackHistoryEntry.fromJson(Map<Object?, Object?>.from(value));
      })),
      localRoots: List<String>.unmodifiable(roots),
      timelineSegments: Map.unmodifiable(segments),
      watchStates: Map.unmodifiable(watchStates),
      trackPreferences: Map.unmodifiable(preferences),
      preferredAudioLanguage:
          readLanguage('preferredAudioLanguage', EmbeddedTrackType.audio),
      preferredSubtitleLanguage:
          readLanguage('preferredSubtitleLanguage', EmbeddedTrackType.subtitle),
      classificationMode: classificationMode as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'states': {
          for (final entry in states.entries) entry.key: entry.value.toJson()
        },
        'bookmarks': {
          for (final entry in bookmarks.entries)
            entry.key: entry.value.map((value) => value.toJson()).toList()
        },
        'history': history.map((value) => value.toJson()).toList(),
        'localRoots': localRoots,
        'timelineSegments': {
          for (final entry in timelineSegments.entries)
            entry.key: entry.value.toJson()
        },
        'watchStates': {
          for (final entry in watchStates.entries)
            entry.key: entry.value.toJson()
        },
        'trackPreferences': {
          for (final entry in trackPreferences.entries)
            entry.key: {
              for (final track in entry.value.entries)
                track.key: {
                  'code': track.value.code,
                  'kind': track.value.kind.name,
                  'label': track.value.label
                }
            }
        },
        if (preferredAudioLanguage != null)
          'preferredAudioLanguage': preferredAudioLanguage,
        if (preferredSubtitleLanguage != null)
          'preferredSubtitleLanguage': preferredSubtitleLanguage,
        if (classificationMode != null) 'classificationMode': classificationMode,
      };

  PortableUserData remap(
      {Map<String, String> localRoots = const {},
      Map<String, String> cloudSources = const {}}) {
    String mapPath(String value) {
      if (value.startsWith('file:')) {
        return 'file:${mapPath(value.substring(5))}';
      }
      final context = p.Context(
          style: RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value)
              ? p.Style.windows
              : p.Style.posix);
      final mappings = localRoots.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length));
      for (final entry in mappings) {
        if (context.equals(entry.key, value) ||
            context.isWithin(entry.key, value)) {
          final result = context.normalize(context.join(
              entry.value, context.relative(value, from: entry.key)));
          return context.style == p.Style.windows
              ? result.toLowerCase()
              : result;
        }
      }
      return value;
    }

    String mapKey(String key) {
      for (final prefix in ['local-work|', 'local-work-id|']) {
        if (key.startsWith(prefix)) {
          final separator = key.lastIndexOf('|');
          if (separator > prefix.length) {
            return '$prefix${mapPath(key.substring(prefix.length, separator))}${key.substring(separator)}';
          }
        }
      }
      if (key.startsWith('local|')) return 'local|${mapPath(key.substring(6))}';
      for (final entry in cloudSources.entries) {
        final workPrefix = 'cloud-work|${entry.key}|';
        if (key.startsWith(workPrefix)) {
          var workKey = key.substring(workPrefix.length);
          if (workKey.startsWith('${entry.key}|')) {
            workKey = '${entry.value}${workKey.substring(entry.key.length)}';
          }
          return 'cloud-work|${entry.value}|$workKey';
        }
        if (key.startsWith('cloud|${entry.key}|')) {
          return 'cloud|${entry.value}|${key.substring(7 + entry.key.length)}';
        }
        if (key.startsWith('${entry.key}|')) {
          var suffix = key.substring(entry.key.length + 1);
          if (suffix.startsWith('${entry.key}|') ||
              suffix.startsWith('${entry.key}:')) {
            suffix = '${entry.value}${suffix.substring(entry.key.length)}';
          }
          return '${entry.value}|$suffix';
        }
      }
      return mapPath(key);
    }

    final mappedStateKeys = states.keys.map(mapKey).toList();
    final mappedBookmarkKeys = bookmarks.keys.map(mapKey).toList();
    if (mappedStateKeys.toSet().length != mappedStateKeys.length ||
        mappedBookmarkKeys.toSet().length != mappedBookmarkKeys.length ||
        [timelineSegments.keys, watchStates.keys, trackPreferences.keys]
            .any((keys) => keys.map(mapKey).toSet().length != keys.length)) {
      throw const FormatException('多个媒体位置对应到同一对象，请分别选择目录');
    }
    return PortableUserData(
      states: {
        for (final entry in states.entries)
          mapKey(entry.key):
              entry.value.copyWith(mediaIds: entry.value.mediaIds.map(mapKey))
      },
      bookmarks: {
        for (final entry in bookmarks.entries) mapKey(entry.key): entry.value
      },
      history: history.map((entry) {
        final json = entry.toJson()
          ..['stableKey'] = mapKey(entry.stableKey)
          ..['sourceId'] = cloudSources[entry.sourceId] ?? entry.sourceId
          ..['posterCachePath'] = null;
        if (!entry.isCloud) json['mediaPath'] = mapPath(entry.mediaPath);
        return PlaybackHistoryEntry.fromJson(json);
      }).toList(),
      localRoots: this.localRoots.map(mapPath).toList(),
      timelineSegments: {
        for (final entry in timelineSegments.entries)
          mapKey(entry.key): entry.value
      },
      watchStates: {
        for (final entry in watchStates.entries) mapKey(entry.key): entry.value
      },
      trackPreferences: {
        for (final entry in trackPreferences.entries)
          mapKey(entry.key): entry.value
      },
      preferredAudioLanguage: preferredAudioLanguage,
      preferredSubtitleLanguage: preferredSubtitleLanguage,
      classificationMode: classificationMode,
    );
  }

  PortableUserData merge(PortableUserData incoming) {
    final mergedStates = Map<String, MediaLibraryUserState>.from(states);
    for (final entry in incoming.states.entries) {
      final existing = mergedStates[entry.key];
      final collections = [
        ...?existing?.collections,
        ...entry.value.collections
      ];
      if (collections.map((name) => name.toLowerCase()).toSet().length >
          MediaLibraryUserState.maxCollections) {
        throw const FormatException('合并后合集超过 20 个，请先整理合集');
      }
      mergedStates[entry.key] = entry.value.copyWith(
        favorite: entry.value.favorite || (existing?.favorite ?? false),
        watchLater: entry.value.watchLater || (existing?.watchLater ?? false),
        collections: collections,
        mediaIds: [...?existing?.mediaIds, ...entry.value.mediaIds],
        categoryOverride: MediaLibraryUserState.mergeClassificationOverride(
            existing?.categoryOverride, entry.value.categoryOverride),
        genreOverride: MediaLibraryUserState.mergeClassificationOverride(
            existing?.genreOverride, entry.value.genreOverride),
      );
    }
    final mergedBookmarks = Map<String, List<PlayerBookmark>>.from(bookmarks);
    for (final entry in incoming.bookmarks.entries) {
      final byPosition = {
        for (final value in entry.value) value.position: value,
        for (final value in bookmarks[entry.key] ?? <PlayerBookmark>[])
          value.position: value
      };
      if (byPosition.length > PlayerBookmarkRepository.maxBookmarksPerMedia) {
        throw const FormatException('合并后书签超过每个视频 100 个，请先整理书签');
      }
      mergedBookmarks[entry.key] = byPosition.values.toList()
        ..sort((a, b) => a.position.compareTo(b.position));
    }
    final mergedHistory = {for (final value in history) value.stableKey: value};
    for (final value in incoming.history) {
      final old = mergedHistory[value.stableKey];
      if (old == null || value.updatedAt.isAfter(old.updatedAt)) {
        mergedHistory[value.stableKey] = value;
      }
    }
    final records = mergedHistory.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final mergedWatch = Map<String, MediaWatchState>.from(watchStates);
    for (final entry in incoming.watchStates.entries) {
      if (mergedWatch[entry.key] == null ||
          entry.value.updatedAt.isAfter(mergedWatch[entry.key]!.updatedAt)) {
        mergedWatch[entry.key] = entry.value;
      }
    }
    final mergedSegments = {...incoming.timelineSegments, ...timelineSegments};
    final mergedPreferences = {
      for (final key in {
        ...incoming.trackPreferences.keys,
        ...trackPreferences.keys
      })
        key: <String, TrackLanguageChoice>{
          ...?incoming.trackPreferences[key],
          ...?trackPreferences[key]
        }
    };
    if ([mergedWatch.length, mergedSegments.length, mergedPreferences.length]
        .any((count) => count > 10000)) {
      throw const FormatException('合并后用户记录超过 10000 项，请先整理');
    }
    return PortableUserData(
        states: mergedStates,
        bookmarks: mergedBookmarks,
        history: records.take(100).toList(),
        localRoots: localRoots,
        timelineSegments: mergedSegments,
        watchStates: mergedWatch,
        trackPreferences: mergedPreferences,
        preferredAudioLanguage:
            preferredAudioLanguage ?? incoming.preferredAudioLanguage,
        preferredSubtitleLanguage:
            preferredSubtitleLanguage ?? incoming.preferredSubtitleLanguage,
        classificationMode: incoming.classificationMode ?? classificationMode);
  }
}
