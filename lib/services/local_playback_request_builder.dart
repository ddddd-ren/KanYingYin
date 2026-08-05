import 'package:kanyingyin/modules/local/local_episode_info.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/modules/roads/road_module.dart';
import 'package:kanyingyin/modules/video/local_playback_request.dart';
import 'package:kanyingyin/modules/local/local_episode.dart';
import 'package:kanyingyin/modules/video/local_playback_session.dart';
import 'package:kanyingyin/modules/video/playback_media_item.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:path/path.dart' as p;

class LocalPlaybackRequestBuilder {
  LocalPlaybackRequestBuilder({
    LocalSubtitleMatcher? subtitleMatcher,
    LocalEpisodeParser? episodeParser,
  })  : _subtitleMatcher = subtitleMatcher ?? LocalSubtitleMatcher(),
        _episodeParser = episodeParser ?? LocalEpisodeParser();

  final LocalSubtitleMatcher _subtitleMatcher;
  final LocalEpisodeParser _episodeParser;

  Future<LocalPlaybackSession> buildSession({
    required String filePath,
    required String fileName,
    List<Map<String, String>>? directoryFiles,
    List<LocalPlaybackEntry>? playbackEntries,
    bool playlistAlreadyIsolated = false,
    bool autoLoadSubtitle = true,
  }) async {
    final normalizedFiles = _normalizePlaylistFiles(
      filePath: filePath,
      fileName: fileName,
      directoryFiles: directoryFiles,
      playbackEntries: playbackEntries,
    );
    final currentFile = _findCurrentFile(normalizedFiles, filePath);
    final files = playlistAlreadyIsolated
        ? normalizedFiles
        : _isolateEpisodePlaylist(
            currentFile: currentFile,
            files: normalizedFiles,
          );
    final episodes = <LocalEpisode>[];
    for (final file in files) {
      final info = _episodeParser.parse(file.parsePath);
      episodes.add(LocalEpisode(
        id: file.location.stableId,
        path: file.path,
        title: file.displayName,
        seasonNumber: info?.seasonNumber,
        episodeNumber: info?.episodeNumber,
        subtitlePath: autoLoadSubtitle
            ? file.subtitlePath ?? await _findSubtitleForFile(file)
            : null,
      ));
    }

    return LocalPlaybackSession(
      seriesId: currentFile.parentLocation.stableId,
      seriesTitle: fileName,
      episodes: List<LocalEpisode>.unmodifiable(episodes),
      currentEpisodeId: currentFile.location.stableId,
    );
  }

  Future<LocalPlaybackRequest> build({
    required String filePath,
    required String fileName,
    String? sourceLabel,
    List<Map<String, String>>? directoryFiles,
    List<LocalPlaybackEntry>? playbackEntries,
    bool playlistAlreadyIsolated = false,
    bool autoLoadSubtitle = true,
  }) async {
    final effectiveSourceLabel = sourceLabel ?? '本地文件';
    final normalizedFiles = _normalizePlaylistFiles(
      filePath: filePath,
      fileName: fileName,
      directoryFiles: directoryFiles,
      playbackEntries: playbackEntries,
    );
    final currentFile = _findCurrentFile(normalizedFiles, filePath);
    final files = playlistAlreadyIsolated
        ? normalizedFiles
        : _isolateEpisodePlaylist(
            currentFile: currentFile,
            files: normalizedFiles,
          );
    final data = files.map((file) => file.path).toList();
    final identifiers = files.map((file) => file.displayName).toList();
    final mediaItem = PlaybackMediaItem(
      id: _stableLocalId(currentFile.parentLocation.stableId),
      title: fileName,
      displayTitle: fileName,
      summary: data.join('\n'),
    );

    final index = data.indexOf(filePath);

    return LocalPlaybackRequest(
      mediaItem: mediaItem,
      sourceLabel: effectiveSourceLabel,
      title: fileName,
      videoPath: filePath,
      currentRoad: 0,
      currentEpisode: index >= 0 ? index + 1 : 1,
      road: Road(
        name: files.length <= 1 ? '播放列表1' : '当前剧集',
        data: data,
        identifier: identifiers,
      ),
      subtitlePath: autoLoadSubtitle
          ? currentFile.subtitlePath ?? await _findSubtitleForFile(currentFile)
          : null,
    );
  }

  Future<String?> findSubtitlePath(String videoPath) {
    return _subtitleMatcher.findForVideo(videoPath);
  }

  List<_PlaylistFile> _normalizePlaylistFiles({
    required String filePath,
    required String fileName,
    List<Map<String, String>>? directoryFiles,
    List<LocalPlaybackEntry>? playbackEntries,
  }) {
    final files = <_PlaylistFile>[];
    final seenLocations = <String>{};
    for (final entry in playbackEntries ?? const <LocalPlaybackEntry>[]) {
      if (!seenLocations.add(entry.location.stableId)) continue;
      files.add(_PlaylistFile.fromEntry(entry));
    }
    for (final file in directoryFiles ?? const <Map<String, String>>[]) {
      final path = file['path'];
      final name = file['name'];
      final title = file['title'];
      if (path == null || path.isEmpty || name == null || name.isEmpty) {
        continue;
      }
      final location = _legacyFileLocation(path);
      if (!seenLocations.add(location.stableId)) {
        continue;
      }
      files.add(_PlaylistFile(
        location: location,
        parentLocation: MediaLocation.file(p.dirname(path)),
        name: name,
        title: title,
      ));
    }

    final containsCurrentFile = files.any((file) => file.path == filePath);
    if (files.isEmpty || !containsCurrentFile) {
      final location = _legacyFileLocation(filePath);
      files.insert(
        0,
        _PlaylistFile(
          location: location,
          parentLocation: MediaLocation.file(p.dirname(filePath)),
          name: fileName,
        ),
      );
    }
    return files;
  }

  List<_PlaylistFile> _isolateEpisodePlaylist({
    required _PlaylistFile currentFile,
    required List<_PlaylistFile> files,
  }) {
    if (files.length <= 1) return files;

    final currentInfo = _episodeParser.parse(currentFile.parsePath);
    if (currentInfo != null) {
      final recognized = files
          .where((file) => _isSameRecognizedSeriesSeason(
                file,
                currentFile,
                currentInfo,
              ))
          .toList(growable: false);
      if (recognized.any((file) => _sameLocation(file, currentFile))) {
        return recognized;
      }
    }

    final filtered = files
        .where((file) => _belongsToCurrentEpisodeGroup(
              file,
              currentFile,
              currentInfo,
            ))
        .toList(growable: false);

    if (filtered.any((file) => _sameLocation(file, currentFile))) {
      return filtered;
    }
    return files.where((file) => _sameLocation(file, currentFile)).toList();
  }

  bool _isSameRecognizedSeriesSeason(
    _PlaylistFile candidate,
    _PlaylistFile current,
    LocalEpisodeInfo currentInfo,
  ) {
    if (_sameLocation(candidate, current)) return true;

    final candidateInfo = _episodeParser.parse(candidate.parsePath);
    if (candidateInfo == null) return false;

    return _sameSeriesSeason(
      currentInfo,
      candidateInfo,
      allowMissingSeason: _sameDirectory(candidate, current),
    );
  }

  bool _belongsToCurrentEpisodeGroup(
    _PlaylistFile candidate,
    _PlaylistFile current,
    LocalEpisodeInfo? currentInfo,
  ) {
    if (_sameLocation(candidate, current)) return true;

    final sameDirectory = _sameDirectory(candidate, current);
    final candidateInfo = _episodeParser.parse(candidate.parsePath);
    if (currentInfo == null) {
      return sameDirectory;
    }

    if (candidateInfo == null) {
      return sameDirectory;
    }

    return _sameSeriesSeason(
      currentInfo,
      candidateInfo,
      allowMissingSeason: sameDirectory,
    );
  }

  bool _sameSeriesSeason(
    LocalEpisodeInfo left,
    LocalEpisodeInfo right, {
    required bool allowMissingSeason,
  }) {
    if (_normalizeSeriesName(left.seriesName) !=
        _normalizeSeriesName(right.seriesName)) {
      return false;
    }

    final leftSeason = left.seasonNumber;
    final rightSeason = right.seasonNumber;
    if (leftSeason == rightSeason) return true;
    if (allowMissingSeason && (leftSeason == null || rightSeason == null)) {
      return true;
    }
    return false;
  }

  bool _sameDirectory(_PlaylistFile left, _PlaylistFile right) {
    return left.parentLocation == right.parentLocation;
  }

  bool _sameLocation(_PlaylistFile left, _PlaylistFile right) {
    return left.location == right.location;
  }

  Future<String?> _findSubtitleForFile(_PlaylistFile file) {
    if (file.location.isDocument) return Future<String?>.value(null);
    return findSubtitlePath(file.path);
  }

  _PlaylistFile _findCurrentFile(
    List<_PlaylistFile> files,
    String filePath,
  ) {
    return files.firstWhere((file) => file.path == filePath);
  }

  MediaLocation _legacyFileLocation(String path) {
    final scheme = Uri.tryParse(path)?.scheme.toLowerCase();
    if (scheme == 'content') {
      throw ArgumentError(
        'Android content URI 必须通过 playbackEntries 提供父级位置',
      );
    }
    return MediaLocation.file(path);
  }

  String _normalizeSeriesName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s._\-]+'), '');
  }

  int _stableLocalId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}

class LocalPlaybackEntry {
  const LocalPlaybackEntry({
    required this.location,
    required this.parentLocation,
    required this.name,
    this.title,
    this.subtitlePath,
  });

  factory LocalPlaybackEntry.fromIndexItem(LocalMediaIndexItem item) {
    return LocalPlaybackEntry(
      location: item.location,
      parentLocation: item.parentLocation,
      name: item.name,
      title: item.displayTitle,
      subtitlePath: item.subtitlePath,
    );
  }

  final MediaLocation location;
  final MediaLocation parentLocation;
  final String name;
  final String? title;
  final String? subtitlePath;
}

class _PlaylistFile {
  final MediaLocation location;
  final MediaLocation parentLocation;
  final String name;
  final String? title;
  final String? subtitlePath;

  const _PlaylistFile({
    required this.location,
    required this.parentLocation,
    required this.name,
    this.title,
    this.subtitlePath,
  });

  factory _PlaylistFile.fromEntry(LocalPlaybackEntry entry) {
    return _PlaylistFile(
      location: entry.location,
      parentLocation: entry.parentLocation,
      name: entry.name,
      title: entry.title,
      subtitlePath: entry.subtitlePath,
    );
  }

  String get path => location.value;

  String get parsePath => location.isFile ? location.value : name;

  String get displayName {
    final value = title?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return name;
  }
}
