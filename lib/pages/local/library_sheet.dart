import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/local_episode_scrape_flow.dart';
import 'package:kanyingyin/pages/local/manual_episode_match_flow.dart';
import 'package:kanyingyin/pages/local/local_series_detail_page.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/pages/local/tmdb_scrape_options_sheet.dart';
import 'package:kanyingyin/repositories/local_media_tag_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

/// 带搜索、排序和 TMDB 信息展示的媒体库面板。
class LibrarySheetContent extends StatefulWidget {
  const LibrarySheetContent({
    super.key,
    required this.controller,
    required this.onPlay,
    required this.onRefresh,
    this.headerActions = const <Widget>[],
    this.tagRepository,
  });

  final LocalController controller;
  final void Function(LocalMediaSeries series, LocalMediaIndexItem episode)
      onPlay;
  final VoidCallback onRefresh;
  final List<Widget> headerActions;
  final ILocalMediaTagRepository? tagRepository;

  @override
  State<LibrarySheetContent> createState() => _LibrarySheetContentState();
}

class _LibrarySheetContentState extends State<LibrarySheetContent> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _sortBy = 'modified';
  final Set<String> _selectedTags = <String>{};
  final MediaLibraryQuery _libraryQuery = const MediaLibraryQuery();
  late final ILocalMediaTagRepository _tagRepository;
  Map<String, List<String>> _customTagsBySeries = <String, List<String>>{};

  @override
  void initState() {
    super.initState();
    _tagRepository = widget.tagRepository ?? LocalMediaTagRepository();
    _reloadCustomTags();
  }

  void _reloadCustomTags() {
    try {
      _customTagsBySeries = _tagRepository.getAll();
    } on Object {
      _customTagsBySeries = <String, List<String>>{};
    }
  }

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
            final library = widget.controller.localMediaLibrary;
            if (library.series.isEmpty) return _empty(context, cs, tt);
            final tagFiltered = _libraryQuery.apply(
              series: library.series,
              sourceId: 'local',
              selectedTags: _selectedTags,
              extraTagsBySeries: _customTagsBySeries,
            );
            final localSeriesKeys =
                tagFiltered.map((item) => item.seriesKey).toSet();
            final all = widget.controller.localLibrarySeries
                .where((item) => localSeriesKeys.contains(item.key))
                .toList(growable: false);
            final series = _filtered(all);
            return Column(
              children: [
                _header(cs, tt, library.series.length),
                _searchBar(cs),
                _tagRow(cs, tt, library),
                if (all.isNotEmpty) _sortRow(cs, tt),
                Expanded(
                  child: series.isEmpty
                      ? Center(
                          child: Text('没有匹配的系列',
                              style:
                                  tt.bodyMedium?.copyWith(color: cs.outline)),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: series.length,
                          itemBuilder: (ctx, i) =>
                              _seriesTile(ctx, cs, tt, series[i]),
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
            '扫描已添加的本地媒体源后，可以按系列查看视频。',
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
            onPressed:
                widget.controller.isIndexingLibrary ? null : widget.onRefresh,
            icon: const Icon(Icons.manage_search_outlined),
            label: const Text('扫描媒体库'),
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
                    '${widget.controller.localLibraryVideoCount} 个视频 · $count 个系列',
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

  Widget _tagRow(ColorScheme cs, TextTheme tt, CloudMediaLibrary library) {
    final availableCategories = _libraryQuery.availableCategories(
      library.series,
      sourceId: 'local',
    );
    final availableGenres = _libraryQuery.availableGenres(
      library.series,
      sourceId: 'local',
    );
    final availableCustomTags = _libraryQuery.availableCustomTags(
      library.series,
      sourceId: 'local',
      customTagsBySeries: _customTagsBySeries,
    );
    final genreStatus = widget.controller.libraryGenreRefreshError;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.sell_outlined, size: 17, color: cs.primary),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: '筛选 TMDB 类型',
              onSelected: (value) => setState(() {
                if (value == '__clear__') {
                  _selectedTags.clear();
                } else if (!_selectedTags.remove(value)) {
                  _selectedTags.add(value);
                }
              }),
              itemBuilder: (_) => _tagMenuEntries(
                availableCategories,
                availableGenres,
                availableCustomTags,
              ),
              child: Text(
                _selectedTags.isEmpty ? '类型' : '类型 ${_selectedTags.length}',
                style: tt.bodySmall,
              ),
            ),
          ]),
          if (widget.controller.isRefreshingLibraryGenres) ...[
            const SizedBox(height: 5),
            Row(children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.controller.libraryGenreRefreshProgress,
                  style: tt.labelSmall?.copyWith(color: cs.outline),
                ),
              ),
            ]),
          ] else if (genreStatus != null) ...[
            const SizedBox(height: 3),
            Row(children: [
              Expanded(
                child: Text(
                  genreStatus,
                  style: tt.labelSmall?.copyWith(color: cs.error),
                ),
              ),
              IconButton(
                tooltip: '刷新类型标签',
                visualDensity: VisualDensity.compact,
                onPressed: widget.controller.refreshLibraryGenres,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _tagMenuEntries(
    List<String> categories,
    List<String> genres,
    List<String> customTags,
  ) {
    final entries = <PopupMenuEntry<String>>[];
    if (_selectedTags.isNotEmpty) {
      entries.add(
        const PopupMenuItem<String>(
          value: '__clear__',
          child: Text('清除'),
        ),
      );
    }
    if (categories.isNotEmpty) {
      entries.add(const PopupMenuItem<String>(
        enabled: false,
        child: Text('分类'),
      ));
      entries.addAll(categories.map(_checkedTagItem));
    }
    if (genres.isNotEmpty) {
      if (entries.isNotEmpty) entries.add(_menuSpacing());
      entries.add(const PopupMenuItem<String>(
        enabled: false,
        child: Text('TMDB 类型'),
      ));
      entries.addAll(genres.map(_checkedTagItem));
    }
    if (customTags.isNotEmpty) {
      if (entries.isNotEmpty) entries.add(_menuSpacing());
      entries.add(const PopupMenuItem<String>(
        enabled: false,
        child: Text('自定义标签'),
      ));
      entries.addAll(customTags.map(_checkedTagItem));
    }
    if (entries.isEmpty ||
        (categories.isEmpty && genres.isEmpty && customTags.isEmpty)) {
      entries.add(const PopupMenuItem<String>(
        enabled: false,
        child: Text('暂无标签，请在作品菜单中添加'),
      ));
    }
    return entries;
  }

  PopupMenuEntry<String> _checkedTagItem(String value) {
    return CheckedPopupMenuItem<String>(
      value: value,
      checked: _selectedTags.contains(value),
      child: Text(value),
    );
  }

  PopupMenuEntry<String> _menuSpacing() {
    return const PopupMenuItem<String>(
      enabled: false,
      height: 8,
      child: SizedBox.shrink(),
    );
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
    final customTags = _customTagsBySeries[series.key] ?? const <String>[];
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
          if (customTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: customTags
                    .map(
                      (tag) => Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelStyle: tt.labelSmall?.copyWith(color: cs.primary),
                        side: BorderSide(color: cs.outlineVariant),
                        backgroundColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '播放选项',
        onSelected: (v) async {
          if (v == 'editTitle') {
            await _editSeriesTitle(ctx, series);
            return;
          }
          if (v == 'editTags') {
            await _editSeriesTags(ctx, series);
            return;
          }
          if (v == 'scrape' || v == 'rematch') {
            await _scrapeSeries(ctx, series, force: v == 'rematch');
            return;
          }
          if (v == 'matchEpisodes') {
            await openLocalManualEpisodeMatch(
              context: ctx,
              controller: widget.controller,
              originalName: series.title,
              paths: series.episodes
                  .map((item) => item.path)
                  .toList(growable: false),
            );
            return;
          }
          if (v == 'details') {
            await Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => LocalSeriesDetailPage(
                series: series,
                controller: widget.controller,
                onPlay: (episode) => widget.onPlay(series, episode),
              ),
            ));
            return;
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'details', child: Text('查看详情')),
          const PopupMenuItem(
            value: 'editTags',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sell_outlined, size: 18),
                SizedBox(width: 8),
                Text('管理标签'),
              ],
            ),
          ),
          const PopupMenuItem(value: 'scrape', child: Text('刮削信息')),
          const PopupMenuItem(value: 'rematch', child: Text('重新匹配')),
          const PopupMenuItem(
            value: 'matchEpisodes',
            child: Text('匹配剧集'),
          ),
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

  Future<void> _editSeriesTags(
    BuildContext context,
    LocalMediaSeries series,
  ) async {
    final initialTags = List<String>.from(
      _customTagsBySeries[series.key] ?? const <String>[],
    );
    final tags = await showDialog<List<String>>(
      context: context,
      builder: (_) => _LocalMediaTagEditorDialog(
        seriesTitle: series.displayTitle,
        initialTags: initialTags,
      ),
    );
    if (!context.mounted || tags == null) return;

    try {
      await _tagRepository.saveForSeries(series.key, tags);
      if (!context.mounted) return;
      setState(() {
        if (tags.isEmpty) {
          _customTagsBySeries.remove(series.key);
        } else {
          _customTagsBySeries[series.key] = List<String>.unmodifiable(tags);
        }
        final availableTags = _libraryQuery
            .availableTags(
              widget.controller.localMediaLibrary.series,
              sourceId: 'local',
              extraTagsBySeries: _customTagsBySeries,
            )
            .toSet();
        _selectedTags.removeWhere(
          (tag) => !availableTags.contains(tag),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标签已保存')),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标签保存失败，请稍后重试')),
      );
    }
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
    final technicalBadges = const MediaTechnicalBadgeResolver().resolve(
      names: [ep.name, ep.path],
      resolution: ep.resolution,
      videoWidth: ep.videoWidth,
      videoHeight: ep.videoHeight,
    );
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (technicalBadges.isNotEmpty) ...[
            const SizedBox(height: 5),
            MediaTechnicalBadgeRow(badges: technicalBadges),
            const SizedBox(height: 4),
          ],
          Text(
            _epSub(ep),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ep.subtitlePath != null)
            Icon(Icons.closed_caption_outlined, size: 18, color: cs.primary),
          PopupMenuButton<String>(
            tooltip: '单集操作',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (value) => _handleEpisodeAction(ctx, ep, value),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'scrape', child: Text('重新识别此集')),
              PopupMenuItem(value: 'match', child: Text('手动匹配此集')),
              PopupMenuItem(value: 'episode', child: Text('匹配季度和集数')),
              PopupMenuItem(value: 'reassign', child: Text('更正作品归属')),
            ],
          ),
        ],
      ),
      onTap: () => widget.onPlay(series, ep),
    );
  }

  Future<void> _handleEpisodeAction(
    BuildContext context,
    LocalMediaIndexItem episode,
    String action,
  ) async {
    switch (action) {
      case 'scrape':
        await scrapeLocalEpisode(
          context: context,
          controller: widget.controller,
          episode: episode,
        );
        return;
      case 'match':
        await openLocalEpisodeTmdbDialog(
          context: context,
          controller: widget.controller,
          episode: episode,
        );
        return;
      case 'episode':
        await openLocalManualEpisodeMatch(
          context: context,
          controller: widget.controller,
          originalName: episode.name,
          paths: <String>[episode.path],
        );
        return;
      case 'reassign':
        await openLocalManualEpisodeMatch(
          context: context,
          controller: widget.controller,
          originalName: episode.name,
          paths: <String>[episode.path],
          reassignSeriesName: true,
        );
        return;
    }
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
          child: TmdbNetworkImage(
              url: remoteUrl,
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

class _LocalMediaTagEditorDialog extends StatefulWidget {
  const _LocalMediaTagEditorDialog({
    required this.seriesTitle,
    required this.initialTags,
  });

  final String seriesTitle;
  final List<String> initialTags;

  @override
  State<_LocalMediaTagEditorDialog> createState() =>
      _LocalMediaTagEditorDialogState();
}

class _LocalMediaTagEditorDialogState
    extends State<_LocalMediaTagEditorDialog> {
  late final TextEditingController _inputController;
  late final List<String> _tags;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _addTag([String? submitted]) {
    final value = (submitted ?? _inputController.text).trim();
    if (value.isEmpty || value.length > LocalMediaTagRepository.maxTagLength) {
      return;
    }
    if (_tags.any((tag) => tag.toLowerCase() == value.toLowerCase())) {
      _inputController.clear();
      return;
    }
    if (_tags.length >= LocalMediaTagRepository.maxTagsPerSeries) return;
    setState(() => _tags.add(value));
    _inputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('管理标签 · ${widget.seriesTitle}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _inputController,
              autofocus: true,
              maxLength: LocalMediaTagRepository.maxTagLength,
              decoration: InputDecoration(
                hintText: '输入标签',
                suffixIcon: IconButton(
                  tooltip: '添加标签',
                  onPressed: _addTag,
                  icon: const Icon(Icons.add),
                ),
              ),
              onSubmitted: _addTag,
            ),
            if (_tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _tags
                      .map(
                        (tag) => InputChip(
                          label: Text(tag),
                          onDeleted: () => setState(() => _tags.remove(tag)),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(List<String>.from(_tags)),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
