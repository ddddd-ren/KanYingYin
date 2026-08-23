import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/history/application/playback_history_controller.dart';
import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final PlaybackHistoryController _history =
      Modular.get<PlaybackHistoryController>();
  final LocalController _local = Modular.get<LocalController>();
  final LocalVideoController _video = Modular.get<LocalVideoController>();
  final CloudPlaybackResolver _cloudResolver = CloudPlaybackResolver();
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_history.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _history,
      builder: (context, _) => KSettingsScaffold(
        title: '观看历史',
        description: '本地媒体和网盘媒体的播放进度会统一保存在这里。',
        actions: [
          IconButton(
            tooltip: '清空历史',
            onPressed: _history.entries.isEmpty ? null : _clearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
        body: _historyBody(),
      ),
    );
  }

  Widget _historyBody() {
    if (!_history.isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = _history.entries;
    if (entries.isEmpty) {
      return const Center(child: Text('暂无观看记录'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: entries.length,
      findItemIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        const prefix = 'history-entry-';
        if (!key.value.startsWith(prefix)) return null;
        final stableKey = key.value.substring(prefix.length);
        final index =
            entries.indexWhere((entry) => entry.stableKey == stableKey);
        return index < 0 ? null : index;
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _HistoryTile(
        key: ValueKey<String>('history-entry-${entries[index].stableKey}'),
        entry: entries[index],
        enabled: !_opening,
        onTap: () => _open(entries[index]),
        onDelete: () => _delete(entries[index]),
      ),
    );
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
    final LocalMediaIndexItem? indexed = _local.localLibraryItems
        .where((candidate) => candidate.path == entry.mediaPath)
        .firstOrNull;
    if (indexed == null) {
      if (!File(entry.mediaPath).existsSync()) {
        throw StateError('本地文件不存在或尚未加入媒体库');
      }
      await _video.openFilePlayback(
        filePath: entry.mediaPath,
        seriesTitle: entry.seriesTitle,
      );
      return;
    }
    // 使用媒体库中同系列剧集恢复原有选集顺序。
    final series = const LocalMediaLibraryBuilder()
        .buildSeries(_local.localLibraryItems)
        .where((value) =>
            value.episodes.any((episode) => episode.path == entry.mediaPath))
        .firstOrNull;
    if (series == null) {
      await _video.openFilePlayback(
        filePath: indexed.path,
        seriesTitle: entry.seriesTitle,
      );
      return;
    }
    final directoryFiles = series.episodes
        .map((episode) => <String, String>{
              'path': episode.path,
              'name': episode.name,
              'title': episode.displayTitle,
            })
        .toList(growable: false);
    final playbackEntries = series.episodes
        .map(LocalPlaybackEntry.fromIndexItem)
        .toList(growable: false);
    await _video.openFilePlayback(
      filePath: entry.mediaPath,
      seriesTitle: series.displayTitle,
      directoryFiles: directoryFiles,
      playbackEntries: playbackEntries,
      playlistAlreadyIsolated: true,
    );
  }

  Future<void> _openCloud(PlaybackHistoryEntry entry) async {
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
        stableId:
            '${candidate.sourceId}:${candidate.remoteId}:${candidate.remotePath}',
        title: candidate.displayName,
        subtitleRemoteId: subtitle?.id,
        subtitleRemotePath: subtitle?.path,
        posterUrl: candidate.tmdbPosterUrl,
        posterCachePath: candidate.posterCachePath,
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
      targets: targets,
      selectedStableId: selected.stableId,
      resolver: _cloudResolver.resolve,
    );
  }

  Future<void> _delete(PlaybackHistoryEntry entry) async {
    await _history.delete(entry.stableKey);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空观看历史'),
        content: const Text('确定删除全部观看记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _history.clear();
  }
}

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
    final theme = Theme.of(context);
    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: SizedBox(
        width: 72,
        height: 88,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _Poster(entry: entry),
        ),
      ),
      title: Text(
        entry.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.isCloud ? '网盘' : '本地'} · 第${entry.episodeIndex}集 · '
              '${_formatDuration(entry.position)} / ${_formatDuration(entry.duration)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ),
      ),
      trailing: IconButton(
        tooltip: '删除记录',
        onPressed: onDelete,
        icon: Icon(Icons.close, color: theme.colorScheme.outline),
      ),
      onTap: onTap,
    );
  }

  static String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
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
        placeholderBuilder: _placeholder,
      );
    }
    final cached = entry.posterCachePath;
    if (cached != null && File(cached).existsSync()) {
      return Image.file(
        File(cached),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }
    final url = entry.posterUrl;
    if (url != null && url.startsWith('http')) {
      return TmdbNetworkImage(
        url: url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(Icons.movie_outlined, color: colors.outline),
    );
  }
}
