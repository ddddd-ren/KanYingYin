import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/bean/dialog/async_confirmation_dialog.dart';
import 'package:kanyingyin/bean/widget/skeleton_loader.dart';
import 'package:kanyingyin/features/history/application/playback_history_controller.dart';
import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';
import 'package:kanyingyin/widgets/poster_cover.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';
import 'package:kanyingyin/utils/time_utils.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;

final _historyEpisodeParser = LocalEpisodeParser();

String _localHistoryMediaId(String path) => path.startsWith('content://')
    ? 'document:$path'
    : LocalMediaIndexItem.normalizePath(path);

bool _matchesCloudHistoryEpisode(
  PlaybackHistoryEntry entry,
  MediaLibraryEpisode episode,
) {
  if (episode.sourceKind != MediaSourceKind.cloud ||
      episode.sourceId != entry.sourceId) {
    return false;
  }
  final remoteId = entry.remoteId?.trim() ?? '';
  return remoteId.isNotEmpty
      ? episode.remoteId == remoteId
      : episode.remotePath != null &&
          CloudSourcePathScope.normalizePath(episode.remotePath!) ==
              CloudSourcePathScope.normalizePath(entry.mediaPath);
}

MediaLibrarySeries? findCloudPlaybackHistorySourceSeries(
  PlaybackHistoryEntry entry,
  Iterable<MediaLibrarySeries> series,
) {
  if (!entry.isCloud) return null;
  final matches = series.where((candidate) =>
      candidate.sourceKind == MediaSourceKind.cloud &&
      candidate.sourceId == entry.sourceId &&
      candidate.episodes.any((episode) =>
          _matchesCloudHistoryEpisode(entry, episode)));
  final unique = matches.take(2).toList(growable: false);
  return unique.length == 1 ? unique.single : null;
}

List<CloudPlaybackTarget> buildCloudPlaybackHistoryTargets(
  MediaLibrarySeries series,
  MediaLibraryEpisode selected, {
  bool useSourcePlaybackIds = false,
}) =>
    [
      for (final episode in series.playbackEpisodesFor(selected))
        if (episode.remoteId != null && episode.remotePath != null)
          CloudPlaybackTarget(
            sourceId: episode.sourceId,
            remoteId: episode.remoteId!,
            remotePath: episode.remotePath!,
            stableId: useSourcePlaybackIds
                ? '${episode.sourceId}:${episode.remoteId}:${episode.remotePath}'
                : episode.stableId,
            title: episode.name,
            episodeNumber: episode.episodeNumber,
            subtitleRemoteId: episode.subtitleRemoteRefs.firstOrNull?.id,
            subtitleRemotePath: episode.subtitleRemoteRefs.firstOrNull?.path,
            posterUrl: episode.tmdbPosterUrl ?? series.tmdbPosterUrl,
            posterCachePath: episode.posterCachePath ?? series.posterCachePath,
            size: episode.size,
            modifiedAt: episode.modifiedAt,
          ),
    ];

String cloudPlaybackHistoryIndexedStableId(
  PlaybackHistoryEntry entry,
  String remoteId,
  String remotePath,
) =>
    entry.stableKey.startsWith('${entry.sourceId}|${entry.sourceId}:')
        ? '${entry.sourceId}:$remoteId:$remotePath'
        : '${entry.sourceId}|$remoteId';

PlaybackHistoryEntry resolvePlaybackHistorySeriesTitle(
  PlaybackHistoryEntry entry,
  Iterable<MediaLibrarySeries> cloudSeries, {
  Map<String, String> localSourceTitlesByMediaId = const <String, String>{},
}) {
  final title = entry.isCloud
      ? findCloudPlaybackHistorySourceSeries(entry, cloudSeries)?.title
      : localSourceTitlesByMediaId[_localHistoryMediaId(entry.mediaPath)];
  if (title == null || title.trim().isEmpty || title == entry.seriesTitle) {
    return entry;
  }
  // 只替换界面快照，避免改名触发观看时间重排或覆盖播放进度。
  return entry.copyWith(seriesTitle: title);
}

String formatPlaybackHistoryTitle(PlaybackHistoryEntry entry) {
  final raw =
      entry.episodeTitle.trim().isEmpty ? entry.mediaPath : entry.episodeTitle;
  final parsed = _historyEpisodeParser.parse(raw);
  final parsedPath = _historyEpisodeParser.parse(entry.mediaPath);
  final rawName = p.basenameWithoutExtension(raw).trim();
  final episodeName =
      parsed == null ? rawName : (parsed.episodeTitle?.trim() ?? '');
  final episodeNumber =
      parsed?.episodeNumber ?? parsedPath?.episodeNumber ?? entry.episodeIndex;
  final seriesTitle = entry.seriesTitle.trim();
  return <String>[
    if (seriesTitle.isNotEmpty) seriesTitle,
    '第$episodeNumber集',
    if (episodeName.isNotEmpty &&
        episodeName.toLowerCase() != seriesTitle.toLowerCase())
      episodeName,
  ].join(' · ');
}

String formatPlaybackHistoryMeta(
  PlaybackHistoryEntry entry,
  String watchedAt,
) {
  final progress = entry.durationSeconds <= 0
      ? 0.0
      : (entry.positionSeconds / entry.durationSeconds).clamp(0.0, 1.0);
  final status = entry.isCompleted ? '已看完' : '已看 ${(progress * 100).round()}%';
  return '${entry.isCloud ? '网盘' : '本地'} · $status · $watchedAt';
}

PlaybackHistoryEntry resolveLocalPlaybackHistoryPoster(
  PlaybackHistoryEntry entry,
  Map<String, LocalMediaIndexItem> localItemsById,
  String? Function(Iterable<String>) posterUrlForPaths,
) {
  if (entry.isCloud) return entry;
  final indexed = localItemsById[_localHistoryMediaId(entry.mediaPath)];
  if (indexed == null) return entry;
  final cachedPoster = entry.posterCachePath?.trim();
  return entry.copyWith(
    posterUrl: entry.posterUrl?.trim().isNotEmpty == true
        ? entry.posterUrl
        : posterUrlForPaths(<String>[indexed.path]),
    posterCachePath: cachedPoster != null &&
            cachedPoster.isNotEmpty &&
            File(cachedPoster).existsSync()
        ? cachedPoster
        : indexed.cover,
  );
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final PlaybackHistoryController _history =
      Modular.get<PlaybackHistoryController>();
  final LocalController _local = Modular.get<LocalController>();
  final CloudResourcesController _cloud =
      Modular.get<CloudResourcesController>();
  final LocalVideoController _video = Modular.get<LocalVideoController>();
  final CloudPlaybackResolver _cloudResolver = CloudPlaybackResolver();
  bool _opening = false;
  bool _showAllHistory = false;

  @override
  void initState() {
    super.initState();
    _local.reloadLocalLibraryIndex();
    unawaited(_history.ensureLoaded());
    unawaited(_ensureSourceTitles());
  }

  Future<void> _ensureSourceTitles() async {
    try {
      await _cloud.ensureMediaLibrarySnapshot();
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'HistoryPage: 来源剧名加载失败，保留观看历史快照',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _history,
        _cloud.mediaLibrarySnapshotListenable,
      ]),
      builder: (context, _) => KSettingsScaffold(
        title: '观看历史',
        actions: [
          IconButton(
            tooltip: '清空历史',
            onPressed: _history.entries.isEmpty ? null : _clearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
        body: Observer(builder: (_) => _historyBody()),
      ),
    );
  }

  Widget _historyBody() {
    if (!_history.isLoaded) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 6,
        itemBuilder: (_, __) => const ListTileSkeleton(),
      );
    }
    final allEntries = _history.entries;
    if (allEntries.isEmpty) {
      return const Center(child: Text('暂无观看记录'));
    }
    final entries = _showAllHistory
        ? allEntries
        : allEntries.where((entry) => !entry.isCompleted).toList();
    final localItemsById = <String, LocalMediaIndexItem>{
      for (final item in _local.localLibraryItems) item.id: item,
    };
    final localSourceTitles = _local.localSourceTitlesByMediaId;
    final cloudSeries = _cloud.mediaLibrarySnapshot.series;
    final rows = <Object>[];
    String? previousSection;
    for (final entry in entries) {
      final section = _dateSection(entry.updatedAt);
      if (section != previousSection) {
        rows.add(section);
        previousSection = section;
      }
      rows.add(entry);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('继续观看'),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('全部历史'),
                  ),
                ],
                selected: <bool>{_showAllHistory},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _showAllHistory = selection.single);
                },
              ),
              const Spacer(),
              Text(
                '${entries.length} 条',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('暂无未看完的记录'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: rows.length,
                  findItemIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    const prefix = 'history-entry-';
                    if (!key.value.startsWith(prefix)) return null;
                    final stableKey = key.value.substring(prefix.length);
                    final index = rows.indexWhere((row) =>
                        row is PlaybackHistoryEntry &&
                        row.stableKey == stableKey);
                    return index < 0 ? null : index;
                  },
                  separatorBuilder: (_, index) {
                    final current = rows[index];
                    final next = rows[index + 1];
                    if (current is! PlaybackHistoryEntry ||
                        next is! PlaybackHistoryEntry) {
                      return const SizedBox.shrink();
                    }
                    return const Divider(height: 1, indent: 56);
                  },
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    if (row is String) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                        child: Text(
                          row,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      );
                    }
                    final original = row as PlaybackHistoryEntry;
                    final entry = resolveLocalPlaybackHistoryPoster(
                      resolvePlaybackHistorySeriesTitle(
                        original,
                        cloudSeries,
                        localSourceTitlesByMediaId: localSourceTitles,
                      ),
                      localItemsById,
                      _local.tmdbPosterUrlForPaths,
                    );
                    return _HistoryTile(
                      key: ValueKey<String>(
                        'history-entry-${entry.stableKey}',
                      ),
                      entry: entry,
                      enabled: !_opening,
                      onTap: () => _open(original),
                      onDelete: () => _delete(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _dateSection(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    final days = today.difference(date).inDays;
    if (days <= 0) return '今天';
    if (days == 1) return '昨天';
    return '更早';
  }

  Future<void> _open(PlaybackHistoryEntry entry) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (entry.source == PlaybackHistorySource.local) {
        await _openLocal(entry);
      } else {
        await _openCloud(entry);
      }
      if (!mounted) return;
      await Modular.to.pushNamed('/video/');
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开媒体：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openLocal(PlaybackHistoryEntry entry) async {
    final resolved = resolvePlaybackHistorySeriesTitle(
      entry,
      const <MediaLibrarySeries>[],
      localSourceTitlesByMediaId: _local.localSourceTitlesByMediaId,
    );
    final LocalMediaIndexItem? indexed = _local.localLibraryItems
        .where((candidate) =>
            candidate.id == _localHistoryMediaId(entry.mediaPath))
        .firstOrNull;
    if (indexed == null) {
      if (!File(entry.mediaPath).existsSync()) {
        throw StateError('本地文件不存在或尚未加入媒体库');
      }
      await _video.openFilePlayback(
        filePath: entry.mediaPath,
        seriesTitle: resolved.seriesTitle,
        legacySeriesTitles: [entry.seriesTitle],
      );
      return;
    }
    // 使用媒体库中同系列剧集恢复原有选集顺序。
    final series = _local.localLibrarySeries
        .where((value) =>
            value.episodes.any((episode) => episode.id == indexed.id))
        .firstOrNull;
    if (series == null) {
      await _video.openFilePlayback(
        filePath: indexed.path,
        seriesTitle: resolved.seriesTitle,
        legacySeriesTitles: [entry.seriesTitle],
      );
      return;
    }
    final directoryFiles = series.episodes
        .map((episode) => <String, String>{
              'path': episode.path,
              'name': episode.name,
              'title': episode.playbackTitleFor(resolved.seriesTitle),
            })
        .toList(growable: false);
    final playbackEntries = series.episodes
        .map((episode) => LocalPlaybackEntry(
              location: episode.location,
              parentLocation: episode.parentLocation,
              name: episode.name,
              title: episode.playbackTitleFor(resolved.seriesTitle),
              subtitlePath: episode.subtitlePath,
            ))
        .toList(growable: false);
    await _video.openFilePlayback(
      filePath: indexed.path,
      seriesTitle: resolved.seriesTitle,
      legacySeriesTitles: series.legacySeriesTitles,
      directoryFiles: directoryFiles,
      playbackEntries: playbackEntries,
      playlistAlreadyIsolated: true,
    );
  }

  Future<void> _openCloud(PlaybackHistoryEntry entry) async {
    await _ensureSourceTitles();
    final sourceSeries = findCloudPlaybackHistorySourceSeries(
      entry,
      _cloud.mediaLibrarySnapshot.series,
    );
    if (sourceSeries != null) {
      final selectedMatches = sourceSeries.episodes
          .where((episode) => _matchesCloudHistoryEpisode(entry, episode))
          .take(2)
          .toList(growable: false);
      if (selectedMatches.length != 1) {
        throw StateError('无法唯一定位来源剧集');
      }
      final selected = selectedMatches.single;
      final targets = buildCloudPlaybackHistoryTargets(
        sourceSeries,
        selected,
        useSourcePlaybackIds: entry.stableKey
            .startsWith('${entry.sourceId}|${entry.sourceId}:'),
      );
      if (targets.isEmpty) throw StateError('网盘文件不在当前媒体库中');
      final selectedTarget = targets.where((target) =>
          target.sourceId == selected.sourceId &&
          target.remoteId == selected.remoteId &&
          target.remotePath == selected.remotePath).single;
      await _video.openCloudPlayback(
        seriesTitle: sourceSeries.title.trim().isEmpty
            ? entry.seriesTitle
            : sourceSeries.title,
        workKey: sourceSeries.seriesKey,
        legacySeriesTitles: sourceSeries.legacySeriesTitles,
        targets: targets,
        selectedStableId: selectedTarget.stableId,
        resolver: _cloudResolver.resolve,
      );
      return;
    }
    await _local.reloadCloudLibraryIndex();
    final indexed = _local.cloudLibraryItems.where(
      (item) =>
          item.sourceId == entry.sourceId &&
          (entry.remoteId == null || item.remoteId == entry.remoteId) &&
          item.remotePath == entry.mediaPath,
    );
    final item = indexed.isEmpty ? null : indexed.first;
    if (item == null) throw StateError('网盘文件不存在或来源不可用');
    final normalizedSeries = item.seriesName.trim().toLowerCase();
    final related = _local.cloudLibraryItems.where((candidate) {
      final sameWork = item.workKey != null &&
          item.workKey!.isNotEmpty &&
          candidate.workKey == item.workKey;
      final sameSeries =
          candidate.seriesName.trim().toLowerCase() == normalizedSeries;
      return candidate.sourceId == item.sourceId && (sameWork || sameSeries);
    }).toList(growable: false)
      ..sort((a, b) {
        final season = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
        if (season != 0) return season;
        final episode = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
        if (episode != 0) return episode;
        return a.name.compareTo(b.name);
      });
    final targets = related.map((candidate) {
      final subtitle = candidate.subtitleRefs.firstOrNull;
      return CloudPlaybackTarget(
        sourceId: candidate.sourceId,
        remoteId: candidate.remoteId,
        remotePath: candidate.remotePath,
        stableId: cloudPlaybackHistoryIndexedStableId(
          entry,
          candidate.remoteId,
          candidate.remotePath,
        ),
        title: candidate.displayName,
        episodeNumber: candidate.episodeNumber,
        subtitleRemoteId: subtitle?.id,
        subtitleRemotePath: subtitle?.path,
        posterUrl: candidate.tmdbPosterUrl,
        posterCachePath: candidate.posterCachePath,
        size: candidate.size,
        modifiedAt: candidate.modifiedAt,
      );
    }).toList(growable: false);
    final selected = targets
        .where((target) =>
            target.remoteId == item.remoteId &&
            target.remotePath == item.remotePath)
        .firstOrNull;
    if (selected == null || targets.isEmpty) {
      throw StateError('网盘文件不在当前媒体库中');
    }
    await _video.openCloudPlayback(
      seriesTitle:
          entry.seriesTitle.isEmpty ? item.seriesName : entry.seriesTitle,
      legacySeriesTitles: [entry.seriesTitle],
      targets: targets,
      selectedStableId: selected.stableId,
      resolver: _cloudResolver.resolve,
    );
  }

  Future<void> _delete(PlaybackHistoryEntry entry) async {
    await _history.delete(entry.stableKey);
  }

  Future<void> _clearHistory() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AsyncConfirmationDialog(
        title: '清空观看历史',
        content: const Text('确定删除全部观看记录吗？'),
        confirmLabel: '清空',
        errorMessage: '清空观看历史失败，请重试',
        onConfirm: _history.clear,
      ),
    );
  }
}

enum _HistoryMenuAction { delete }

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    super.key,
    required this.entry,
    required this.enabled,
    required this.onTap,
    required this.onDelete,
  });

  final PlaybackHistoryEntry entry;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final progress = entry.durationSeconds <= 0
        ? 0.0
        : (entry.positionSeconds / entry.durationSeconds)
            .clamp(0.0, 1.0)
            .toDouble();
    final watchedAt = TimeUtils.formatTimestampToRelativeTime(
      entry.updatedAt.millisecondsSinceEpoch ~/ 1000,
    );
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: SizedBox(
        width: 44,
        height: 66,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: _Poster(entry: entry),
        ),
      ),
      title: Text(
        formatPlaybackHistoryTitle(entry),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatPlaybackHistoryMeta(entry, watchedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ),
      ),
      trailing: PopupMenuButton<_HistoryMenuAction>(
        enabled: enabled,
        tooltip: '更多操作',
        onSelected: (action) {
          if (action == _HistoryMenuAction.delete) onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem<_HistoryMenuAction>(
            value: _HistoryMenuAction.delete,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline),
                SizedBox(width: 10),
                Text('删除记录'),
              ],
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.entry});

  final PlaybackHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.isCloud) {
      return CloudPosterImage(
        cachePath: entry.posterCachePath,
        url: TmdbMatchSheet.imageUrl(entry.posterUrl, size: 'w500'),
        fit: BoxFit.cover,
      );
    }
    return PosterCover(child: _localOrNetworkPoster());
  }

  Widget _localOrNetworkPoster() {
    final cached = entry.posterCachePath;
    if (cached != null && File(cached).existsSync()) {
      return Image.file(
        File(cached),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const PosterCover.placeholder(),
      );
    }
    final url = entry.posterUrl;
    if (url != null && url.startsWith('http')) {
      return TmdbNetworkImage(
        url: url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const PosterCover.placeholder(),
      );
    }
    return const PosterCover.placeholder();
  }
}
