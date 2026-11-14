import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';

typedef MediaCategoryCloudPlaybackResolver = Future<CloudResolvedPlayback>
    Function(CloudPlaybackTarget target);

/// 媒体库功能访问本地媒体的最小端口。
abstract interface class LocalLibraryPort {
  CloudMediaLibrary get library;

  CloudMediaLibrary get cachedLibrary;

  void reloadAvailableLibrary({bool includeUnavailable = false});
}

/// 媒体库功能访问网盘媒体的最小端口。
abstract interface class CloudLibraryPort {
  CloudMediaLibrary get library;

  CloudMediaLibrary get cachedLibrary;

  Listenable get changes;

  Future<void> ensureLibrary();

  Future<void> refreshLibrary();

  Future<void> hideEpisodes(Iterable<MediaLibraryEpisode> episodes);
}

/// 媒体库功能请求播放的最小端口。
abstract interface class PlaybackPort {
  Future<void> openFile({
    required String filePath,
    required String seriesTitle,
    List<String>? legacySeriesTitles,
    List<Map<String, String>>? directoryFiles,
    List<LocalPlaybackEntry>? playbackEntries,
    bool playlistAlreadyIsolated,
    bool autoLoadSubtitle,
  });

  Future<void> openCloud({
    required String seriesTitle,
    String? workKey,
    List<String>? legacySeriesTitles,
    required List<CloudPlaybackTarget> targets,
    required String selectedStableId,
    MediaCategoryCloudPlaybackResolver? resolver,
  });
}
