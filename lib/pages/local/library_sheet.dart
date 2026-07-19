import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/local_series_detail_page.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/pages/local/tmdb_scrape_options_sheet.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

ImageProvider<Object>? cloudSeriesCoverProvider(MediaLibrarySeries series) {
  final cachePath = series.posterCachePath?.trim() ?? '';
  if (cachePath.isNotEmpty) return FileImage(File(cachePath));
  final networkUrl = TmdbMatchSheet.imageUrl(series.tmdbPosterUrl);
  return networkUrl == null ? null : NetworkImage(networkUrl);
}

/// 带搜索、排序和 TMDB 信息展示的媒体库面板。
class LibrarySheetContent extends StatefulWidget {
  const LibrarySheetContent({
    super.key,
    required this.controller,
    required this.onPlay,
    required this.onRefresh,
    this.onPlayCloud,
    this.headerActions = const <Widget>[],
  });

  final LocalController controller;
  final void Function(LocalMediaSeries series, LocalMediaIndexItem episode)
      onPlay;
  final VoidCallback onRefresh;
  final FutureOr<void> Function(
    MediaLibrarySeries series,
    MediaLibraryEpisode episode,
  )? onPlayCloud;
  final List<Widget> headerActions;

  @override
  State<LibrarySheetContent> createState() => _LibrarySheetContentState();
}

class _LibrarySheetContentState extends State<LibrarySheetContent> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _sortBy = 'modified';
  String? _openingCloudStableId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<LocalMediaSeries> _filtered(List<LocalMediaSeries> all) {
    var list = all;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((s) {
        return s.displayTitle.toLowerCase().contains(q) ||
            _bn(s).toLowerCase().contains(q);
      }).toList();
    }
    switch (_sortBy) {
      case 'name':
        list.sort((a, b) => a.displayTitle
            .toLowerCase()
            .compareTo(b.displayTitle.toLowerCase()));
        break;
      case 'rating':
        list.sort((a, b) => _rt(b).compareTo(_rt(a)));
        break;
      default:
        list.sort((a, b) => b.latestModified.compareTo(a.latestModified));
    }
    return list;
  }

  String _bn(LocalMediaSeries s) {
    for (final ep in s.episodes) {
      final title = ep.tmdb?.title;
      if (title != null && title.isNotEmpty) return title;
      final originalTitle = ep.tmdb?.originalTitle;
      if (originalTitle != null && originalTitle.isNotEmpty) {
        return originalTitle;
      }
    }
    return '';
  }

  double _rt(LocalMediaSeries s) {
    for (final ep in s.episodes) {
      final r = ep.tmdb?.rating;
      if (r != null && r > 0) return r;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollCtrl) {
        return Observer(
          builder: (_) {
            final library = widget.controller.combinedMediaLibrary;
            if (library.series.isEmpty) return _empty(context, cs, tt);
            final selected = widget.controller.selectedLibrarySourceId;
            final all = selected == 'all' || selected == 'local'
                ? widget.controller.localLibrarySeries
                : <LocalMediaSeries>[];
            final series = _filtered(all);
            final cloudSeries = library
                .filterBySource(selected)
                .where((item) => item.sourceKind == MediaSourceKind.cloud)
                .where((item) =>
                    _query.isEmpty ||
                    item.title.toLowerCase().contains(_query.toLowerCase()))
                .toList(growable: false);
            return Column(
              children: [
                _header(cs, tt, library.series.length),
                _searchBar(cs),
                _sourceRow(cs, tt, library),
                if (all.isNotEmpty) _sortRow(cs, tt),
                Expanded(
                  child: series.isEmpty && cloudSeries.isEmpty
                      ? Center(
                          child: Text('没有匹配的系列',
                              style:
                                  tt.bodyMedium?.copyWith(color: cs.outline)),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: series.length + cloudSeries.length,
                          itemBuilder: (ctx, i) => i < series.length
                              ? _seriesTile(ctx, cs, tt, series[i])
                              : _cloudSeriesTile(
                                  ctx, cs, tt, cloudSeries[i - series.length]),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _empty(BuildContext context, ColorScheme cs, TextTheme tt) {
    CloudSource? selectedCloudSource;
    final selected = widget.controller.selectedLibrarySourceId;
    if (selected != 'all' && selected != 'local') {
      for (final source in widget.controller.cloudLibrarySources) {
        if (source.id == selected) {
          selectedCloudSource = source;
          break;
        }
      }
    }
    final cloudSource = selectedCloudSource;
    final message = cloudSource == null
        ? '扫描已添加的本地或网盘媒体源后，可以按系列查看视频。'
        : switch (cloudSource.scanStatus) {
            CloudScanStatus.never => '该网盘来源尚未扫描',
            CloudScanStatus.scanning => '正在扫描网盘目录，请稍候',
            CloudScanStatus.failed => '上次扫描失败，请检查连接和目录权限',
            CloudScanStatus.completed => cloudSource.lastScanFailureCount > 0
                ? '没有找到视频，且 ${cloudSource.lastScanFailureCount} 个目录读取失败'
                : '扫描目录中没有找到支持的视频',
          };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_collection_outlined, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text('媒体库还没有内容', style: tt.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: cs.outline),
          ),
          const SizedBox(height: 18),
          if (widget.headerActions.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: widget.headerActions,
            ),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            onPressed: cloudSource == null
                ? widget.controller.isIndexingLibrary
                    ? null
                    : widget.onRefresh
                : cloudSource.scanStatus == CloudScanStatus.scanning
                    ? null
                    : () => _refreshCloudSource(context, cloudSource.id),
            icon: const Icon(Icons.manage_search_outlined),
            label: Text(cloudSource == null ? '扫描媒体库' : '重新扫描网盘'),
          ),
        ],
      ),
    );
  }

  Widget _header(ColorScheme cs, TextTheme tt, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('媒体库', style: tt.titleMedium),
                const SizedBox(height: 2),
                Text(
                    '${widget.controller.combinedMediaLibrary.series.fold<int>(0, (sum, item) => sum + item.episodes.length)} 个视频 · $count 个系列',
                    style: tt.bodySmall?.copyWith(color: cs.outline)),
              ],
            ),
          ),
          ...widget.headerActions,
          IconButton(
            tooltip: '重新扫描',
            onPressed:
                widget.controller.isIndexingLibrary ? null : widget.onRefresh,
            icon: widget.controller.isIndexingLibrary
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.manage_search_outlined),
          ),
        ]),
      );

  Widget _searchBar(ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: SizedBox(
          height: 36,
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索系列名称',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      }),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
      );

  Widget _sourceRow(ColorScheme cs, TextTheme tt, CloudMediaLibrary library) {
    final selected = widget.controller.selectedLibrarySourceId;
    var current = library.filters.first;
    for (final filter in library.filters) {
      if (filter.id == selected) current = filter;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(children: [
        Icon(
          current.kind == MediaSourceKind.cloud
              ? Icons.cloud_outlined
              : current.kind == MediaSourceKind.local
                  ? Icons.folder_outlined
                  : Icons.video_library_outlined,
          size: 18,
          color: cs.primary,
        ),
        const SizedBox(width: 6),
        PopupMenuButton<String>(
          tooltip: '筛选媒体来源',
          initialValue: selected,
          onSelected: (value) => setState(() {
            widget.controller.selectLibrarySource(value);
          }),
          itemBuilder: (_) => library.filters
              .map((filter) => PopupMenuItem<String>(
                    value: filter.id,
                    child: Text(filter.label),
                  ))
              .toList(growable: false),
          child: Text(current.label, style: tt.bodySmall),
        ),
      ]),
    );
  }

  Widget _cloudSeriesTile(BuildContext context, ColorScheme cs, TextTheme tt,
      MediaLibrarySeries series) {
    final rating = series.tmdbRating;
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      leading:
          Tooltip(message: series.sourceName, child: _cloudCover(cs, series)),
      title: Text(series.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          '${series.episodes.length} 集',
          series.sourceName,
          if (rating != null && rating > 0) '${rating.toStringAsFixed(1)} ★',
          if (!series.isAvailable) '当前不可用',
        ].join(' · '),
        style: tt.labelSmall?.copyWith(color: cs.outline),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '网盘系列操作',
        onSelected: (value) =>
            _scrapeCloudSeries(context, series, force: value == 'rematch'),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'scrape', child: Text('TMDB 刮削')),
          PopupMenuItem(value: 'rematch', child: Text('重新匹配')),
        ],
      ),
      children: [
        if (series.tmdbOverview?.trim().isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              series.tmdbOverview!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(color: cs.outline, height: 1.4),
            ),
          ),
        ...series.episodes.map((episode) => ListTile(
              dense: true,
              leading: _openingCloudStableId == episode.stableId
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(series.isAvailable
                      ? Icons.play_circle_outline
                      : Icons.cloud_off_outlined),
              title: Text(episode.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(episode.remotePath ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: _openingCloudStableId == null
                  ? () => _openCloudEpisode(context, series, episode)
                  : null,
            )),
      ],
    );
  }

  Widget _cloudCover(ColorScheme cs, MediaLibrarySeries series) {
    final networkUrl = TmdbMatchSheet.imageUrl(series.tmdbPosterUrl);
    final provider = cloudSeriesCoverProvider(series);
    Widget fallbackIcon() => Icon(
          series.isAvailable ? Icons.cloud_outlined : Icons.cloud_off_outlined,
          color: series.isAvailable ? cs.primary : cs.outline,
        );
    Widget fallbackNetwork() => networkUrl != null
        ? Image.network(
            networkUrl,
            width: 40,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallbackIcon(),
          )
        : fallbackIcon();
    final cachePath = series.posterCachePath?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: provider == null
          ? fallbackIcon()
          : Image(
              image: provider,
              width: 40,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  cachePath.isEmpty ? fallbackIcon() : fallbackNetwork(),
            ),
    );
  }

  Future<void> _openCloudEpisode(
    BuildContext context,
    MediaLibrarySeries series,
    MediaLibraryEpisode episode,
  ) async {
    if (!episode.isAvailable || widget.onPlayCloud == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(episode.isAvailable
            ? '网盘播放暂不可用，请稍后重试'
            : '${episode.sourceName} 已离线或禁用，旧索引已保留'),
        action: SnackBarAction(
          label: widget.controller.refreshingCloudSourceIds
                  .contains(episode.sourceId)
              ? '刷新中'
              : '刷新',
          onPressed: () => _refreshCloudSource(context, episode.sourceId),
        ),
      ));
      return;
    }
    setState(() => _openingCloudStableId = episode.stableId);
    try {
      await widget.onPlayCloud!(series, episode);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('网盘视频解析失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _openingCloudStableId = null);
    }
  }

  Future<void> _refreshCloudSource(
      BuildContext context, String sourceId) async {
    if (widget.controller.refreshingCloudSourceIds.contains(sourceId)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('该网盘来源正在刷新')));
      return;
    }
    final success = await widget.controller.refreshCloudLibrarySource(sourceId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? '网盘来源已刷新'
          : widget.controller.cloudRefreshError ?? '网盘来源暂时无法刷新'),
    ));
  }

  Future<void> _scrapeCloudSeries(
      BuildContext context, MediaLibrarySeries series,
      {required bool force}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.controller.scrapeCloudSeries(
        series,
        forceManual: force,
      );
      if (!context.mounted) return;
      if (result.selected != null) {
        messenger
            .showSnackBar(const SnackBar(content: Text('网盘影片 TMDB 信息已更新')));
        return;
      }
      if (result.candidates.isEmpty) {
        messenger
            .showSnackBar(const SnackBar(content: Text('没有找到匹配的 TMDB 信息')));
        return;
      }
      final selected = await showModalBottomSheet<TmdbMetadata>(
        context: context,
        isScrollControlled: true,
        builder: (_) => TmdbMatchSheet(
          seriesName: series.title,
          candidates: result.candidates,
        ),
      );
      if (selected == null || !context.mounted) return;
      await widget.controller.selectCloudTmdbCandidate(series, selected);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('已使用所选 TMDB 信息')));
    } on Object catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(error is StateError
            ? error.message.toString()
            : '网盘影片 TMDB 刮削失败，请稍后重试'),
      ));
    }
  }

  Widget _sortRow(ColorScheme cs, TextTheme tt) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(children: [
          _chip(cs, tt, '名称', 'name'),
          const SizedBox(width: 6),
          _chip(cs, tt, '更新时间', 'modified'),
          const SizedBox(width: 6),
          _chip(cs, tt, '评分', 'rating'),
        ]),
      );

  Widget _chip(ColorScheme cs, TextTheme tt, String label, String field) {
    final active = _sortBy == field;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = field),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: tt.bodySmall
                ?.copyWith(color: active ? cs.onPrimaryContainer : cs.outline)),
      ),
    );
  }

  Widget _seriesTile(
      BuildContext ctx, ColorScheme cs, TextTheme tt, LocalMediaSeries series) {
    final info = _infoLine(series);
    final cover = _coverUrl(series);
    final summary = _summary(series);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(left: 8, right: 4, bottom: 8),
      leading: _cover(cs, series.cover, remoteUrl: cover),
      title: Text(series.displayTitle,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${series.episodeCount} 集 · 更新 ${_fmt(series.latestModified)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(color: cs.outline)),
          if (info.isNotEmpty)
            Text(info,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall
                    ?.copyWith(color: cs.primary, fontWeight: FontWeight.w500)),
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '播放选项',
        onSelected: (v) async {
          if (v == 'editTitle') {
            await _editSeriesTitle(ctx, series);
            return;
          }
          if (v == 'scrape' || v == 'rematch') {
            await _scrapeSeries(ctx, series, force: v == 'rematch');
            return;
          }
          if (v == 'details') {
            await Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => LocalSeriesDetailPage(
                series: series,
                onPlay: (episode) => widget.onPlay(series, episode),
              ),
            ));
            return;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'details', child: Text('查看详情')),
          const PopupMenuItem(value: 'scrape', child: Text('刮削信息')),
          const PopupMenuItem(value: 'rematch', child: Text('重新匹配')),
          const PopupMenuItem(value: 'editTitle', child: Text('修改剧名')),
        ],
      ),
      children: [
        if (summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: cs.outline, height: 1.4)),
          ),
        for (final ep in series.episodes) _epTile(ctx, cs, tt, series, ep),
      ],
    );
  }

  Future<void> _scrapeSeries(
    BuildContext context,
    LocalMediaSeries series, {
    required bool force,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final options = await showModalBottomSheet<TmdbScrapeOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TmdbScrapeOptionsSheet(
        initialOptions: widget.controller.tmdbScrapeOptions,
      ),
    );
    if (options == null || !context.mounted) return;
    final result = await widget.controller.scrapeSeriesWithTmdb(
      series.title,
      force: force,
      options: options,
    );
    if (!context.mounted) return;
    if (result.status == TmdbScrapeStatus.matched) {
      messenger.showSnackBar(SnackBar(
        content: Text(result.posterDownloadFailures > 0
            ? 'TMDB 信息已更新，部分封面下载失败'
            : 'TMDB 信息已更新'),
      ));
      return;
    }
    if (result.status == TmdbScrapeStatus.none) {
      messenger.showSnackBar(
        const SnackBar(content: Text('请先在设置中填写 TMDB API Key')),
      );
      return;
    }
    if (result.status == TmdbScrapeStatus.failed) {
      messenger.showSnackBar(const SnackBar(content: Text('TMDB 刮削失败')));
      return;
    }

    final selected = await showModalBottomSheet<TmdbMetadata>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TmdbMatchSheet(
        seriesName: series.title,
        candidates: result.candidates,
      ),
    );
    if (selected == null || !context.mounted) return;
    final selectedResult = await widget.controller.selectTmdbCandidate(
      series.title,
      selected,
      options: options,
    );
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(selectedResult.status != TmdbScrapeStatus.matched
          ? '保存匹配结果失败'
          : selectedResult.posterDownloadFailures > 0
              ? '已使用所选 TMDB 信息，部分封面下载失败'
              : '已使用所选 TMDB 信息'),
    ));
  }

  Future<void> _editSeriesTitle(
    BuildContext context,
    LocalMediaSeries series,
  ) async {
    final input = TextEditingController(text: series.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改剧名'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(hintText: '输入剧名'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(input.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    input.dispose();
    if (!context.mounted || title == null || title.trim().isEmpty) return;

    final updated = await widget.controller.updateLocalSeriesTitle(
      series.episodes.map((item) => item.path),
      title,
    );
    if (!context.mounted || !updated) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('剧名已更新')),
    );
  }

  Widget _epTile(BuildContext ctx, ColorScheme cs, TextTheme tt,
      LocalMediaSeries series, LocalMediaIndexItem ep) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8, right: 4),
      leading: const Icon(Icons.play_circle_outline, size: 22),
      title: Row(children: [
        Expanded(
            child: Text(ep.displayTitle,
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (ep.manualOverride)
          Padding(
              padding: const EdgeInsets.only(left: 6),
              child:
                  Icon(Icons.edit_note_outlined, size: 16, color: cs.primary)),
      ]),
      subtitle: Text(
        _epSub(ep),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.labelSmall?.copyWith(color: cs.outline),
      ),
      trailing: ep.subtitlePath != null
          ? Icon(Icons.closed_caption_outlined, size: 18, color: cs.primary)
          : null,
      onTap: () => widget.onPlay(series, ep),
    );
  }

  String _epSub(LocalMediaIndexItem ep) {
    final item = ep.toFileItem();
    final tech = item.episodeInfo?.technicalLabel ?? '';
    return [
      if (item.hasEpisodeInfo) item.episodeInfo!.episodeLabel,
      if (tech.isNotEmpty) tech,
      item.formattedDuration,
      item.formattedResolution,
      item.formattedSize,
    ].where((p) => p.isNotEmpty).join('  ');
  }

  Widget _cover(ColorScheme cs, String? cover, {String? remoteUrl}) {
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(remoteUrl,
              width: 40,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => cover != null && cover.isNotEmpty
                  ? Image.file(File(cover),
                      width: 40,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                            Icons.movie_creation_outlined,
                            color: cs.primary,
                          ))
                  : Icon(Icons.movie_creation_outlined, color: cs.primary)));
    }
    if (cover != null && cover.isNotEmpty) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(File(cover),
              width: 40,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.movie_creation_outlined, color: cs.primary)));
    }
    return Icon(Icons.movie_creation_outlined, color: cs.primary);
  }

  String _infoLine(LocalMediaSeries s) {
    String name = '';
    double? r;
    String? d;
    for (final ep in s.episodes) {
      final metadata = ep.tmdb;
      if (metadata != null && metadata.title.isNotEmpty) {
        name = metadata.title;
        r = metadata.rating;
        d = metadata.releaseDate;
        break;
      }
    }
    if (name.isEmpty) return '';
    final parts = <String>[name];
    if (r != null && r > 0) parts.add('${r.toStringAsFixed(1)} ★');
    if (d != null && d.length >= 4) parts.add(d.substring(0, 4));
    return parts.join(' · ');
  }

  String _coverUrl(LocalMediaSeries s) {
    for (final ep in s.episodes) {
      final url = TmdbMatchSheet.imageUrl(ep.tmdb?.posterUrl);
      if (url != null) return url;
    }
    return '';
  }

  String _summary(LocalMediaSeries s) {
    for (final ep in s.episodes) {
      final t = ep.tmdb?.overview;
      if (t != null && t.isNotEmpty) return t;
    }
    return '';
  }

  String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
