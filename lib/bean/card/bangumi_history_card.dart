import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/modules/history/history_module.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/local_media_scanner.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:path/path.dart' as p;

enum HistoryMediaAvailability {
  localAvailable,
  localMissing,
  cloudAvailable,
  cloudOffline,
}

bool isCloudHistorySource({
  required String sourceType,
  required String sourceIdentity,
}) =>
    HistorySourceType.fromValue(sourceType) == HistorySourceType.cloud ||
    parseCloudHistoryIdentity(sourceIdentity) != null;

HistoryMediaAvailability resolveHistoryMediaAvailability({
  required String sourceType,
  required String sourceIdentity,
  required Iterable<MediaLibrarySeries> cloudSeries,
}) {
  if (isCloudHistorySource(
    sourceType: sourceType,
    sourceIdentity: sourceIdentity,
  )) {
    final identity = parseCloudHistoryIdentity(sourceIdentity);
    if (identity == null) return HistoryMediaAvailability.cloudOffline;
    for (final series in cloudSeries) {
      if (series.sourceId != identity.sourceId || !series.isAvailable) continue;
      for (final episode in series.episodes) {
        if (episode.isAvailable &&
            episode.remotePath?.toLowerCase() ==
                identity.remotePath.toLowerCase()) {
          return HistoryMediaAvailability.cloudAvailable;
        }
      }
    }
    return HistoryMediaAvailability.cloudOffline;
  }
  return File(sourceIdentity).existsSync()
      ? HistoryMediaAvailability.localAvailable
      : HistoryMediaAvailability.localMissing;
}

String historyMediaAvailabilityLabel(HistoryMediaAvailability availability) =>
    switch (availability) {
      HistoryMediaAvailability.localAvailable => '本地文件',
      HistoryMediaAvailability.localMissing => '文件已移动或删除',
      HistoryMediaAvailability.cloudAvailable => '网盘文件',
      HistoryMediaAvailability.cloudOffline => '网盘离线',
    };

// 视频历史记录卡片 - 水平布局
class BangumiHistoryCardV extends StatefulWidget {
  const BangumiHistoryCardV({
    super.key,
    required this.historyItem,
    this.showDelete = false,
    this.onDeleted,
  });

  final History historyItem;
  final bool showDelete;
  final VoidCallback? onDeleted;

  @override
  State<BangumiHistoryCardV> createState() => _BangumiHistoryCardVState();
}

class _BangumiHistoryCardVState extends State<BangumiHistoryCardV> {
  final LocalVideoController localVideoController =
      Modular.get<LocalVideoController>();
  final LocalController localController = Modular.get<LocalController>();
  final CloudPlaybackResolver _cloudPlaybackResolver = CloudPlaybackResolver();

  Future<void> _onTap() async {
    if (widget.showDelete) {
      AppDialog.showToast(message: '编辑模式');
      return;
    }
    if (isCloudHistorySource(
      sourceType: widget.historyItem.sourceType,
      sourceIdentity: widget.historyItem.lastSrc,
    )) {
      await _openCloudHistory();
    } else {
      await _openLocalHistory();
    }
  }

  Future<void> _openCloudHistory() async {
    final identity = parseCloudHistoryIdentity(widget.historyItem.lastSrc);
    if (identity == null) {
      AppDialog.showToast(message: '网盘历史记录已损坏');
      return;
    }
    await localController.reloadCloudLibraryIndex();
    MediaLibrarySeries? matchedSeries;
    MediaLibraryEpisode? matchedEpisode;
    for (final series in localController.combinedMediaLibrary.series) {
      if (series.sourceId != identity.sourceId || !series.isAvailable) continue;
      for (final episode in series.episodes) {
        if (episode.remotePath.toString().toLowerCase() ==
            identity.remotePath.toLowerCase()) {
          matchedSeries = series;
          matchedEpisode = episode;
          break;
        }
      }
      if (matchedEpisode != null) break;
    }
    if (matchedSeries == null || matchedEpisode == null) {
      AppDialog.showToast(message: '网盘视频已移动或来源不可用');
      return;
    }
    final targets = matchedSeries.episodes
        .map((episode) => CloudPlaybackTarget(
              sourceId: episode.sourceId,
              remotePath: episode.remotePath!,
              stableId: episode.stableId,
              title: episode.name,
              subtitleRemotePath: episode.subtitleRemotePaths.firstOrNull,
            ))
        .toList(growable: false);
    final resumePositionSeconds = widget
            .historyItem
            .progresses[widget.historyItem.lastWatchEpisode]
            ?.progress
            .inSeconds ??
        0;
    await localVideoController.openCloudPlayback(
      seriesTitle: matchedSeries.title,
      targets: targets,
      selectedStableId: matchedEpisode.stableId,
      resolver: _cloudPlaybackResolver.resolve,
      resumePositionSeconds: resumePositionSeconds,
    );
    if (!mounted) return;
    Modular.to.pushNamed('/video/');
  }

  Future<void> _openLocalHistory() async {
    final filePath = widget.historyItem.lastSrc;
    final file = File(filePath);
    if (!file.existsSync()) {
      AppDialog.showToast(message: '文件已移动或删除');
      return;
    }

    final directoryFiles = <Map<String, String>>[];
    try {
      final scanner = LocalMediaScanner();
      final scanResult = await scanner.scan(
        p.dirname(filePath),
        sortMode: LocalSortMode.name,
        ascending: true,
      );
      for (final item in scanResult.items) {
        if (item.isVideo) {
          directoryFiles.add({'path': item.path, 'name': item.name});
        }
      }
    } catch (e) {
      AppLogger().w('History: failed to scan local playlist', error: e);
    }

    final progress =
        widget.historyItem.progresses[widget.historyItem.lastWatchEpisode];
    localVideoController.openFilePlayback(
      filePath: filePath,
      seriesTitle: widget.historyItem.bangumiItem.nameCn.isNotEmpty
          ? widget.historyItem.bangumiItem.nameCn
          : widget.historyItem.bangumiItem.name,
      directoryFiles: directoryFiles,
      resumePositionSeconds: progress?.progress.inSeconds ?? 0,
    );
    Modular.to.pushNamed('/video/');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final double imageWidth = 80;
    final double imageHeight = 108;
    final String title = widget.historyItem.bangumiItem.nameCn == ''
        ? widget.historyItem.bangumiItem.name
        : widget.historyItem.bangumiItem.nameCn;
    final String episodeText = widget.historyItem.lastWatchEpisodeName.isEmpty
        ? '第${widget.historyItem.lastWatchEpisode}话'
        : widget.historyItem.lastWatchEpisodeName;
    final availability = resolveHistoryMediaAvailability(
      sourceType: widget.historyItem.sourceType,
      sourceIdentity: widget.historyItem.lastSrc,
      cloudSeries: localController.combinedMediaLibrary.series,
    );
    final available = availability == HistoryMediaAvailability.localAvailable ||
        availability == HistoryMediaAvailability.cloudAvailable;
    final isCloud = isCloudHistorySource(
      sourceType: widget.historyItem.sourceType,
      sourceIdentity: widget.historyItem.lastSrc,
    );

    return Dismissible(
      key: ValueKey(widget.historyItem.key),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        widget.onDeleted?.call();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline,
          color: colorScheme.onErrorContainer,
        ),
      ),
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: _onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: imageWidth,
                    height: imageHeight,
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      isCloud
                          ? available
                              ? Icons.cloud_outlined
                              : Icons.cloud_off_outlined
                          : available
                              ? Icons.video_file_outlined
                              : Icons.file_present_outlined,
                      color:
                          available ? colorScheme.primary : colorScheme.error,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: imageHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.play_circle_outline,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                episodeText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.extension_outlined,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                historyMediaAvailabilityLabel(availability),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              Utils.formatTimestampToRelativeTime(widget
                                      .historyItem
                                      .lastWatchTime
                                      .millisecondsSinceEpoch ~/
                                  1000),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.showDelete)
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: colorScheme.error,
                        ),
                        tooltip: '删除记录',
                        onPressed: () {
                          widget.onDeleted?.call();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
