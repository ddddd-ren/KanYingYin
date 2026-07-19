import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/cloud/cloud_media_path_parser.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:path/path.dart' as p;

@immutable
class CloudSeriesEpisodeIdentity {
  const CloudSeriesEpisodeIdentity({
    required this.sourceId,
    required this.parentPath,
    required this.seriesName,
    required this.normalizedSeriesName,
    required this.seasonNumber,
    required this.episodeNumber,
  });

  final String sourceId;
  final String parentPath;
  final String seriesName;
  final String normalizedSeriesName;
  final int? seasonNumber;
  final int episodeNumber;

  String get stableKey => '$sourceId|$parentPath|$normalizedSeriesName';
}

class CloudSeriesIdentityResolver {
  CloudSeriesIdentityResolver({CloudMediaPathParser? mediaPathParser})
      : _mediaPathParser = mediaPathParser ?? CloudMediaPathParser();

  final CloudMediaPathParser _mediaPathParser;

  CloudSeriesEpisodeIdentity? resolve({
    required String sourceId,
    required String remotePath,
    required int size,
    required int minSizeBytes,
  }) {
    final normalizedPath = normalizeRemotePath(remotePath);
    if (sourceId.trim().isEmpty ||
        !LocalVideoFileTypes.isRecognizedVideo(
          normalizedPath,
          size: size,
          minSizeBytes: minSizeBytes,
        )) {
      return null;
    }
    final episode = _mediaPathParser.parse(normalizedPath);
    if (!episode.isEpisode || episode.episodeNumber == null) return null;
    final seriesName = episode.seriesName!.trim();
    final normalizedSeriesName = normalizeSeriesName(seriesName);
    if (normalizedSeriesName.isEmpty) return null;
    return CloudSeriesEpisodeIdentity(
      sourceId: sourceId.trim(),
      parentPath: p.posix.dirname(normalizedPath),
      seriesName: seriesName,
      normalizedSeriesName: normalizedSeriesName,
      seasonNumber: episode.seasonNumber,
      episodeNumber: episode.episodeNumber!,
    );
  }

  static String normalizeRemotePath(String value) {
    var result = value.trim().replaceAll('\\', '/');
    result = result.replaceAll(RegExp(r'/+'), '/');
    if (result.isEmpty) return '/';
    if (!result.startsWith('/')) result = '/$result';
    if (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String normalizeSeriesName(String value) => value
      .trim()
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();
}
