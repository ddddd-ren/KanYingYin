import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:path/path.dart' as p;

enum CloudMediaType { movie, series, episode, special, unknown }

class CloudMediaIndexItem {
  static const int currentRecognitionVersion = 13;

  const CloudMediaIndexItem({
    required this.sourceId,
    required this.remoteId,
    required this.remotePath,
    required this.name,
    String? remoteName,
    String? displayName,
    this.workKey,
    this.workRootId,
    this.workRootPath,
    required this.size,
    required this.modifiedAt,
    required this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.mediaType = CloudMediaType.unknown,
    this.subtitlePaths = const <String>[],
    List<CloudRemoteRef> subtitleRefs = const <CloudRemoteRef>[],
    this.tmdbId,
    this.tmdbTitle,
    this.tmdbOriginalTitle,
    this.tmdbOverview,
    this.tmdbRating,
    this.tmdbPosterUrl,
    this.tmdbBackdropUrl,
    this.posterCachePath,
    this.tmdbGenres = const <String>[],
    this.recognitionVersion = currentRecognitionVersion,
    this.releaseTags = const MediaReleaseTags(),
  })  : remoteName = remoteName ?? name,
        displayName = displayName ?? name,
        _subtitleRefs = subtitleRefs;

  final String sourceId;
  final String remoteId;
  final String remotePath;
  final String name;
  final String remoteName;
  final String displayName;
  final String? workKey;
  final String? workRootId;
  final String? workRootPath;
  final int size;
  final DateTime? modifiedAt;
  final String seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final CloudMediaType mediaType;
  final List<String> subtitlePaths;
  final List<CloudRemoteRef> _subtitleRefs;

  /// 旧索引没有字幕文件 ID 时继续按路径工作。
  List<CloudRemoteRef> get subtitleRefs => _subtitleRefs.isNotEmpty
      ? _subtitleRefs
      : subtitlePaths
          .map((path) => CloudRemoteRef(id: path, path: path))
          .toList(growable: false);
  final int? tmdbId;
  final String? tmdbTitle;
  final String? tmdbOriginalTitle;
  final String? tmdbOverview;
  final double? tmdbRating;
  final String? tmdbPosterUrl;
  final String? tmdbBackdropUrl;
  final String? posterCachePath;
  final List<String> tmdbGenres;
  final int recognitionVersion;
  final MediaReleaseTags releaseTags;

  bool get needsRecognitionRefresh =>
      recognitionVersion < currentRecognitionVersion ||
      remoteName.isEmpty ||
      displayName.isEmpty ||
      (mediaType == CloudMediaType.episode &&
          (workKey == null || workKey!.trim().isEmpty));

  CloudMediaIndexItem copyWith({
    String? displayName,
    String? seriesName,
    int? tmdbId,
    String? tmdbTitle,
    String? tmdbOriginalTitle,
    String? tmdbOverview,
    double? tmdbRating,
    String? tmdbPosterUrl,
    String? tmdbBackdropUrl,
    String? posterCachePath,
    List<String>? tmdbGenres,
  }) =>
      CloudMediaIndexItem(
        sourceId: sourceId,
        remoteId: remoteId,
        remotePath: remotePath,
        name: name,
        remoteName: remoteName,
        displayName: displayName ?? this.displayName,
        workKey: workKey,
        workRootId: workRootId,
        workRootPath: workRootPath,
        size: size,
        modifiedAt: modifiedAt,
        seriesName: seriesName ?? this.seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        mediaType: mediaType,
        subtitlePaths: subtitlePaths,
        subtitleRefs: subtitleRefs,
        tmdbId: tmdbId ?? this.tmdbId,
        tmdbTitle: tmdbTitle ?? this.tmdbTitle,
        tmdbOriginalTitle: tmdbOriginalTitle ?? this.tmdbOriginalTitle,
        tmdbOverview: tmdbOverview ?? this.tmdbOverview,
        tmdbRating: tmdbRating ?? this.tmdbRating,
        tmdbPosterUrl: tmdbPosterUrl ?? this.tmdbPosterUrl,
        tmdbBackdropUrl: tmdbBackdropUrl ?? this.tmdbBackdropUrl,
        posterCachePath: posterCachePath ?? this.posterCachePath,
        tmdbGenres: tmdbGenres ?? this.tmdbGenres,
        recognitionVersion: recognitionVersion,
        releaseTags: releaseTags,
      );

  CloudMediaIndexItem withEffectiveWorkTitle(String title) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', '作品标题不能为空');
    }
    final season = seasonNumber;
    final episode = episodeNumber;
    final virtualName = season != null && episode != null
        ? '$normalizedTitle S${season.toString().padLeft(2, '0')}'
            'E${episode.toString().padLeft(2, '0')}${p.extension(remoteName)}'
        : displayName;
    return copyWith(
      displayName: virtualName,
      seriesName: normalizedTitle,
    );
  }

  CloudMediaIndexItem withEpisodeMapping({
    required int? seasonNumber,
    required int? episodeNumber,
    required bool keepOriginal,
    int? tmdbId,
  }) {
    final title = tmdbTitle?.trim().isNotEmpty == true
        ? tmdbTitle!.trim()
        : seriesName.trim();
    final virtualName = !keepOriginal &&
            title.isNotEmpty &&
            seasonNumber != null &&
            episodeNumber != null
        ? '$title S${seasonNumber.toString().padLeft(2, '0')}'
            'E${episodeNumber.toString().padLeft(2, '0')}${p.extension(remoteName)}'
        : remoteName;
    return CloudMediaIndexItem(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      name: name,
      remoteName: remoteName,
      displayName: virtualName,
      workKey: workKey,
      workRootId: workRootId,
      workRootPath: workRootPath,
      size: size,
      modifiedAt: modifiedAt,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      mediaType: CloudMediaType.episode,
      subtitlePaths: subtitlePaths,
      subtitleRefs: subtitleRefs,
      tmdbId: tmdbId ?? this.tmdbId,
      tmdbTitle: tmdbTitle,
      tmdbOriginalTitle: tmdbOriginalTitle,
      tmdbOverview: tmdbOverview,
      tmdbRating: tmdbRating,
      tmdbPosterUrl: tmdbPosterUrl,
      tmdbBackdropUrl: tmdbBackdropUrl,
      posterCachePath: posterCachePath,
      tmdbGenres: tmdbGenres,
      recognitionVersion: recognitionVersion,
      releaseTags: releaseTags,
    );
  }

  CloudMediaIndexItem replaceTmdb({
    required int tmdbId,
    required String tmdbTitle,
    String? tmdbOriginalTitle,
    String? tmdbOverview,
    double? tmdbRating,
    String? tmdbPosterUrl,
    String? tmdbBackdropUrl,
    String? posterCachePath,
    List<String>? tmdbGenres,
  }) =>
      CloudMediaIndexItem(
        sourceId: sourceId,
        remoteId: remoteId,
        remotePath: remotePath,
        name: name,
        remoteName: remoteName,
        displayName: displayName,
        workKey: workKey,
        workRootId: workRootId,
        workRootPath: workRootPath,
        size: size,
        modifiedAt: modifiedAt,
        seriesName: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        mediaType: mediaType,
        subtitlePaths: subtitlePaths,
        subtitleRefs: subtitleRefs,
        tmdbId: tmdbId,
        tmdbTitle: tmdbTitle,
        tmdbOriginalTitle: tmdbOriginalTitle,
        tmdbOverview: tmdbOverview,
        tmdbRating: tmdbRating,
        tmdbPosterUrl: tmdbPosterUrl,
        tmdbBackdropUrl: tmdbBackdropUrl,
        posterCachePath: posterCachePath,
        tmdbGenres: tmdbGenres ?? this.tmdbGenres,
        recognitionVersion: recognitionVersion,
        releaseTags: releaseTags,
      );
}
