import 'package:kanyingyin/features/library/presentation/library_media_grid.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';

/// 将本地媒体领域数据转换为媒体库卡片所需的只读展示数据。
class LibraryMediaViewDataBuilder {
  const LibraryMediaViewDataBuilder();

  LibraryMediaItemViewData build(
    LocalVideoGroup group, {
    required bool isScraping,
    String? networkCoverUrl,
  }) {
    final first = group.firstEpisode;
    return LibraryMediaItemViewData(
      id: first.path,
      title: group.title,
      subtitle: group.subtitle,
      infoText: group.hasMultipleEpisodes
          ? buildSeriesInfoText(group)
          : buildItemInfoText(first),
      mediaInfoText: first.hasMediaInfo && !group.hasMultipleEpisodes
          ? buildMediaInfoText(first)
          : '',
      modifiedText: latestModifiedText(group),
      hasMultipleEpisodes: group.hasMultipleEpisodes,
      hasSubtitle: group.episodes.any((item) => item.hasSubtitle),
      scrapeLabel: isScraping
          ? '正在刮削'
          : group.needsOnlinePoster
              ? '未刮削'
              : '已刮削',
      localCoverPath: group.cover,
      networkCoverUrl: networkCoverUrl,
      isScraping: isScraping,
      preferLocalCover: !group.needsOnlinePoster,
      heroTag: first.path,
    );
  }

  String buildMediaSourceSubtitle(
    LocalMediaSource source, {
    required bool isAvailable,
  }) {
    if (!isAvailable) return '目录不可访问，可移除这条记录';
    final scanText = source.lastScannedAt == null
        ? '未扫描'
        : '上次扫描 ${formatSourceScanTime(source.lastScannedAt!)}';
    return '${source.directoryCount} 个文件夹  '
        '${source.videoCount} 个视频  $scanText';
  }

  String formatSourceScanTime(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
        '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
  }

  String buildItemInfoText(
    LocalFileItem item, {
    bool includeModified = false,
  }) {
    final parts = [
      if (item.extension.isNotEmpty) item.extension,
      if (item.hasEpisodeInfo) item.episodeInfo!.episodeLabel,
      item.formattedSize,
      if (includeModified) item.formattedModified,
    ].where((part) => part.isNotEmpty);
    return parts.join('  ');
  }

  String buildSeriesInfoText(LocalVideoGroup group) {
    final extensions = group.episodes
        .map((item) => item.extension)
        .where((extension) => extension.isNotEmpty)
        .toSet();
    final totalSize =
        group.episodes.fold<int>(0, (total, item) => total + item.size);
    final sizeText = formatBytes(totalSize);
    return [
      if (extensions.isNotEmpty) extensions.join('/'),
      sizeText,
    ].where((part) => part.isNotEmpty).join('  ');
  }

  String latestModifiedText(LocalVideoGroup group) {
    final latest = group.episodes
        .map((item) => item.modified)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    return '${latest.year}-${_twoDigits(latest.month)}-'
        '${_twoDigits(latest.day)}';
  }

  String formatBytes(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String buildMediaInfoText(LocalFileItem item) {
    final parts = [
      item.formattedDuration,
      item.formattedResolution,
    ].where((part) => part.isNotEmpty);
    return parts.join('  ');
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
