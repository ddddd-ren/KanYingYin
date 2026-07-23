import 'package:kanyingyin/modules/local/local_episode_info.dart';
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

  LocalPlaybackSession buildSession({
    required String filePath,
    required String fileName,
    List<Map<String, String>>? directoryFiles,
    bool playlistAlreadyIsolated = false,
    bool autoLoadSubtitle = true,
  }) {
    final normalizedFiles = _normalizePlaylistFiles(
      filePath: filePath,
      fileName: fileName,
      directoryFiles: directoryFiles,
    );
    final files = playlistAlreadyIsolated
        ? normalizedFiles
        : _isolateEpisodePlaylist(
            filePath: filePath,
            files: normalizedFiles,
          );
    final episodes = files.map((file) {
      final info = _episodeParser.parse(file.path);
      return LocalEpisode(
        id: _normalizePath(file.path),
        path: file.path,
        title: file.displayName,
        seasonNumber: info?.seasonNumber,
        episodeNumber: info?.episodeNumber,
        subtitlePath: autoLoadSubtitle ? findSubtitlePath(file.path) : null,
      );
    }).toList(growable: false);

    return LocalPlaybackSession(
      seriesId: _normalizePath(p.dirname(filePath)),
      seriesTitle: fileName,
      episodes: episodes,
      currentEpisodeId: _normalizePath(filePath),
    );
  }

  LocalPlaybackRequest build({
    required String filePath,
    required String fileName,
    String? sourceLabel,
    List<Map<String, String>>? directoryFiles,
    bool playlistAlreadyIsolated = false,
    bool autoLoadSubtitle = true,
  }) {
    final effectiveSourceLabel = sourceLabel ?? '本地文件';
    final dirPath = p.dirname(filePath);
    final normalizedFiles = _normalizePlaylistFiles(
      filePath: filePath,
      fileName: fileName,
      directoryFiles: directoryFiles,
    );
    final files = playlistAlreadyIsolated
        ? normalizedFiles
        : _isolateEpisodePlaylist(
            filePath: filePath,
            files: normalizedFiles,
          );
    final data = files.map((file) => file.path).toList();
    final identifiers = files.map((file) => file.displayName).toList();
    final mediaItem = PlaybackMediaItem(
      id: _stableLocalId(dirPath),
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
      subtitlePath: autoLoadSubtitle ? findSubtitlePath(filePath) : null,
    );
  }

  String? findSubtitlePath(String videoPath) {
    return _subtitleMatcher.findForVideo(videoPath);
  }

  List<_PlaylistFile> _normalizePlaylistFiles({
    required String filePath,
    required String fileName,
    List<Map<String, String>>? directoryFiles,
  }) {
    final files = <_PlaylistFile>[];
    final seenPaths = <String>{};
    for (final file in directoryFiles ?? const <Map<String, String>>[]) {
      final path = file['path'];
      final name = file['name'];
      final title = file['title'];
      if (path == null || path.isEmpty || name == null || name.isEmpty) {
        continue;
      }
      if (!seenPaths.add(path)) {
        continue;
      }
      files.add(_PlaylistFile(path: path, name: name, title: title));
    }

    final containsCurrentFile = files.any((file) => file.path == filePath);
    if (files.isEmpty || !containsCurrentFile) {
      files.insert(0, _PlaylistFile(path: filePath, name: fileName));
    }
    return files;
  }

  List<_PlaylistFile> _isolateEpisodePlaylist({
    required String filePath,
    required List<_PlaylistFile> files,
  }) {
    if (files.length <= 1) return files;

    final currentInfo = _episodeParser.parse(filePath);
    if (currentInfo != null) {
      final recognized = files
          .where((file) => _isSameRecognizedSeriesSeason(
                file.path,
                filePath,
                currentInfo,
              ))
          .toList(growable: false);
      if (recognized.any((file) => _samePath(file.path, filePath))) {
        return recognized;
      }
    }

    final filtered = files
        .where((file) => _belongsToCurrentEpisodeGroup(
              file.path,
              filePath,
              currentInfo,
            ))
        .toList(growable: false);

    if (filtered.any((file) => _samePath(file.path, filePath))) {
      return filtered;
    }
    return files.where((file) => _samePath(file.path, filePath)).toList();
  }

  bool _isSameRecognizedSeriesSeason(
    String candidatePath,
    String currentPath,
    LocalEpisodeInfo currentInfo,
  ) {
    if (_samePath(candidatePath, currentPath)) return true;

    final candidateInfo = _episodeParser.parse(candidatePath);
    if (candidateInfo == null) return false;

    return _sameSeriesSeason(
      currentInfo,
      candidateInfo,
      allowMissingSeason: _sameDirectory(candidatePath, currentPath),
    );
  }

  bool _belongsToCurrentEpisodeGroup(
    String candidatePath,
    String currentPath,
    LocalEpisodeInfo? currentInfo,
  ) {
    if (_samePath(candidatePath, currentPath)) return true;

    final sameDirectory = _sameDirectory(candidatePath, currentPath);
    final candidateInfo = _episodeParser.parse(candidatePath);
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

  bool _sameDirectory(String leftPath, String rightPath) {
    return _normalizePath(p.dirname(leftPath)) ==
        _normalizePath(p.dirname(rightPath));
  }

  bool _samePath(String leftPath, String rightPath) {
    return _normalizePath(leftPath) == _normalizePath(rightPath);
  }

  String _normalizePath(String value) {
    return p.normalize(value).toLowerCase();
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

class _PlaylistFile {
  final String path;
  final String name;
  final String? title;

  const _PlaylistFile({
    required this.path,
    required this.name,
    this.title,
  });

  String get displayName {
    final value = title?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return name;
  }
}
