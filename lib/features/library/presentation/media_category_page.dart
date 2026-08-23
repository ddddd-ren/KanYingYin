import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/features/library/application/media_card_info.dart';
import 'package:kanyingyin/features/library/presentation/media_library_details_dialog.dart';
import 'package:kanyingyin/features/tv/presentation/tv_layout_policy.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

class MediaCategoryPage extends StatefulWidget {
  const MediaCategoryPage({
    super.key,
    required this.category,
    required this.initialize,
    required this.libraryProvider,
    required this.onPlayEpisode,
    this.onHideEpisodes,
    this.observeLibrary = true,
    this.capabilities,
  });

  final MediaLibraryCategory category;
  final Future<void> Function() initialize;
  final MediaCategoryLibraryProvider libraryProvider;
  final MediaCategoryEpisodeAction onPlayEpisode;
  final MediaCategoryHideEpisodesAction? onHideEpisodes;
  final bool observeLibrary;
  final AppPlatformCapabilities? capabilities;

  @override
  State<MediaCategoryPage> createState() => _MediaCategoryPageState();
}

class _MediaCategoryPageState extends State<MediaCategoryPage> {
  static const MediaLibraryQuery _queryService = MediaLibraryQuery();

  String _sourceId = 'all';
  String _keyword = '';
  bool _loading = true;
  bool _playing = false;
  String? _errorMessage;
  String? _posterWarmupIdentity;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      await widget.initialize();
    } on Object {
      _errorMessage = '媒体分类加载失败，请稍后重试';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  CloudMediaLibrary _library() {
    return widget.libraryProvider();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.observeLibrary
        ? Observer(builder: (_) => _buildContent())
        : Builder(builder: (_) => _buildContent());
    return Scaffold(
      body: SafeArea(child: content),
    );
  }

  Widget _buildContent() {
    final library = _library();
    final sourceId = library.filters.any(
      (filter) => filter.id == _sourceId,
    )
        ? _sourceId
        : 'all';
    final series = _queryService.apply(
      series: library.series,
      sourceId: sourceId,
      keyword: _keyword,
      selectedTags: <String>{widget.category.label},
    );
    return Column(
      children: [
        _header(context, library, series.length, sourceId),
        _searchBar(),
        Expanded(child: _content(context, series)),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    CloudMediaLibrary library,
    int count,
    String sourceId,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
      child: Row(
        children: [
          Icon(_categoryIcon(), color: colors.primary),
          const SizedBox(width: 10),
          Text(
            widget.category.label,
            key: const ValueKey<String>('media-category-title'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count 部',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.outline,
                ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const ValueKey<String>(
                      'media-category-source-filter',
                    ),
                    value: sourceId,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(8),
                    items: [
                      for (final filter in library.filters)
                        DropdownMenuItem<String>(
                          value: filter.id,
                          child: Text(
                            filter.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _sourceId = value);
                    },
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '刷新分类',
            onPressed: _loading ? null : _initialize,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: TextField(
        key: const ValueKey<String>('media-category-search'),
        decoration: InputDecoration(
          hintText: '搜索${widget.category.label}',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
        ),
        onChanged: (value) => setState(() => _keyword = value.trim()),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    List<MediaLibrarySeries> series,
  ) {
    if (_loading && series.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final errorMessage = _errorMessage;
    if (errorMessage != null && series.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(errorMessage),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _initialize,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (series.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_categoryIcon(), size: 48),
            const SizedBox(height: 12),
            Text('还没有${widget.category.label}'),
          ],
        ),
      );
    }
    final policy = TvLayoutPolicy.forCapabilities(
      widget.capabilities ?? detectAppPlatform(),
    );
    _scheduleCloudPosterWarmup(context, series);
    return FocusTraversalGroup(
      key: const ValueKey<String>('media-category-focus-group'),
      child: GridView.builder(
        padding: policy.gridPadding(const EdgeInsets.all(12)),
        gridDelegate: policy.posterGridDelegate(
          fallbackMaxCrossAxisExtent: 280,
          fallbackChildAspectRatio: 0.68,
        ),
        itemCount: series.length,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          const prefix = 'media-category-card-';
          if (!key.value.startsWith(prefix)) return null;
          final seriesKey = key.value.substring(prefix.length);
          final index = series.indexWhere((item) => item.key == seriesKey);
          return index < 0 ? null : index;
        },
        itemBuilder: (context, index) => _seriesCard(context, series[index]),
      ),
    );
  }

  Widget _seriesCard(BuildContext context, MediaLibrarySeries series) {
    final info = UnifiedMediaCardInfoBuilder.forSeries(
      series,
      categoryLabel: widget.category.label,
    );
    return ImmersiveMediaCard(
      key: ValueKey<String>('media-category-card-${series.key}'),
      cover: _cover(context, series),
      title: info.title,
      subtitle: info.subtitle,
      details: info.details,
      overlayMode: ImmersiveMediaCardOverlayMode.hover,
      badges: info.badges,
      technicalBadges: info.technicalBadges,
      trailing: _seriesMenu(series),
      onTap: !series.isAvailable || _playing ? null : () => _openSeries(series),
    );
  }

  Widget _seriesMenu(MediaLibrarySeries series) {
    return Material(
      type: MaterialType.transparency,
      shape: const CircleBorder(),
      child: PopupMenuButton<_MediaCategoryAction>(
        tooltip: '媒体操作',
        padding: EdgeInsets.zero,
        iconSize: 16,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(32),
          maximumSize: const Size.square(32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.more_vert),
        onSelected: (action) => _handleSeriesAction(series, action),
        itemBuilder: (_) => <PopupMenuEntry<_MediaCategoryAction>>[
          PopupMenuItem<_MediaCategoryAction>(
            value: _MediaCategoryAction.play,
            child: Text(series.episodes.length == 1 ? '播放' : '播放剧集'),
          ),
          const PopupMenuItem<_MediaCategoryAction>(
            value: _MediaCategoryAction.details,
            child: Text('媒体详情'),
          ),
          if (series.sourceKind == MediaSourceKind.local)
            const PopupMenuItem<_MediaCategoryAction>(
              value: _MediaCategoryAction.copyPath,
              child: Text('复制路径'),
            ),
          if (series.sourceKind == MediaSourceKind.cloud &&
              widget.onHideEpisodes != null) ...[
            const PopupMenuDivider(),
            const PopupMenuItem<_MediaCategoryAction>(
              value: _MediaCategoryAction.hide,
              child: Text('隐藏视频'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleSeriesAction(
    MediaLibrarySeries series,
    _MediaCategoryAction action,
  ) async {
    switch (action) {
      case _MediaCategoryAction.play:
        await _openSeries(series);
        return;
      case _MediaCategoryAction.details:
        await showMediaLibraryDetailsDialog(
          context: context,
          series: series,
        );
        return;
      case _MediaCategoryAction.copyPath:
        final path = series.episodes.firstOrNull?.localItem?.path;
        if (path == null || path.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: path));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('路径已复制')),
        );
        return;
      case _MediaCategoryAction.hide:
        final selected = await _selectEpisodesToHide(series);
        if (selected == null || selected.isEmpty || !mounted) return;
        try {
          await widget.onHideEpisodes?.call(series, selected);
          if (!mounted) return;
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已隐藏 ${selected.length} 个视频')),
          );
        } on Object {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('隐藏设置保存失败，请重试')),
          );
        }
        return;
    }
  }

  Future<List<MediaLibraryEpisode>?> _selectEpisodesToHide(
    MediaLibrarySeries series,
  ) {
    final policy = TvLayoutPolicy.forCapabilities(
      widget.capabilities ?? detectAppPlatform(),
    );
    final dialogWidth = policy.dialogMaxWidth(560);
    final episodes = series.episodes;
    if (episodes.isEmpty) {
      return Future<List<MediaLibraryEpisode>?>.value(null);
    }
    if (episodes.length == 1) {
      final episode = episodes.single;
      return showDialog<List<MediaLibraryEpisode>>(
        context: context,
        builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogWidth),
          child: FocusTraversalGroup(
            key: const ValueKey<String>('media-category-dialog-focus-group'),
            child: AlertDialog(
              title: const Text('隐藏视频'),
              content: Text(
                '确定从分类海报墙隐藏“${episode.name}”吗？\n\n'
                '只会修改看影音中的显示，不会删除网盘文件。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    <MediaLibraryEpisode>[episode],
                  ),
                  child: const Text('隐藏'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return showDialog<List<MediaLibraryEpisode>>(
      context: context,
      builder: (context) => _MediaCategoryHideDialog(
        episodes: episodes,
        maxWidth: dialogWidth,
      ),
    );
  }

  Widget _cover(BuildContext context, MediaLibrarySeries series) {
    final colors = Theme.of(context).colorScheme;
    Widget placeholder() => ColoredBox(
          color: colors.surfaceContainerHighest,
          child: Center(
            child: Icon(
              _categoryIcon(),
              size: 52,
              color: colors.primary,
            ),
          ),
        );
    if (series.sourceKind == MediaSourceKind.cloud) {
      return CloudPosterImage(
        cachePath: series.posterCachePath,
        url: _tmdbImageUrl(series.tmdbPosterUrl),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholderBuilder: (_) => placeholder(),
      );
    }
    final cached = series.posterCachePath;
    if (cached != null && cached.isNotEmpty && File(cached).existsSync()) {
      return Image.file(
        File(cached),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _networkCover(series, placeholder),
      );
    }
    return _networkCover(series, placeholder);
  }

  void _scheduleCloudPosterWarmup(
    BuildContext context,
    List<MediaLibrarySeries> series,
  ) {
    final limit = cloudPosterWarmupLimit(
      MediaQuery.sizeOf(context),
      maxCrossAxisExtent: 280,
      childAspectRatio: 0.68,
    );
    final paths = series
        .where((item) => item.sourceKind == MediaSourceKind.cloud)
        .take(limit)
        .map((item) => item.posterCachePath)
        .toList(growable: false);
    final identity = paths.map((path) => path?.trim() ?? '').join('\u0000');
    if (_posterWarmupIdentity == identity) return;
    _posterWarmupIdentity = identity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _posterWarmupIdentity != identity) return;
      unawaited(precacheCloudPosterFiles(context, paths, limit: limit));
    });
  }

  Widget _networkCover(
    MediaLibrarySeries series,
    Widget Function() placeholder,
  ) {
    final url = _tmdbImageUrl(series.tmdbPosterUrl);
    if (url == null) return placeholder();
    return TmdbNetworkImage(
      url: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => placeholder(),
    );
  }

  Future<void> _openSeries(MediaLibrarySeries series) async {
    if (series.episodes.isEmpty) return;
    final episode = series.episodes.length == 1
        ? series.episodes.single
        : await _selectEpisode(series);
    if (episode == null || !mounted) return;
    setState(() => _playing = true);
    try {
      await widget.onPlayEpisode(series, episode);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频加载失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<MediaLibraryEpisode?> _selectEpisode(MediaLibrarySeries series) {
    return showModalBottomSheet<MediaLibraryEpisode>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FocusTraversalGroup(
          key: const ValueKey<String>('media-category-episode-focus-group'),
          child: FractionallySizedBox(
            heightFactor: 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          series.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: series.episodes.length,
                    itemBuilder: (context, index) {
                      final episode = series.episodes[index];
                      final local = episode.localItem;
                      final technicalBadges =
                          const MediaTechnicalBadgeResolver().resolve(
                        names: [
                          episode.name,
                          if (local != null) local.path,
                          if (episode.remotePath != null) episode.remotePath!,
                        ],
                        resolution: local?.resolution,
                        videoWidth: local?.videoWidth,
                        videoHeight: local?.videoHeight,
                      );
                      final detailsText =
                          episode.sourceKind == MediaSourceKind.local
                              ? local?.path ?? ''
                              : episode.remotePath ?? '';
                      return Focus(
                        autofocus: index == 0,
                        child: ListTile(
                          leading: const Icon(Icons.play_circle_outline),
                          title: Text(
                            episode.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (technicalBadges.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                MediaTechnicalBadgeRow(
                                  badges: technicalBadges,
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                detailsText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          onTap: () => Navigator.of(context).pop(episode),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon() => switch (widget.category) {
        MediaLibraryCategory.movie => Icons.movie_outlined,
        MediaLibraryCategory.anime => Icons.animation_outlined,
        MediaLibraryCategory.tvSeries => Icons.live_tv_outlined,
      };

  String? _tmdbImageUrl(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return normalized;
    }
    final path = normalized.startsWith('/') ? normalized : '/$normalized';
    return 'https://image.tmdb.org/t/p/w500$path';
  }
}

enum _MediaCategoryAction { play, details, copyPath, hide }

class _MediaCategoryHideDialog extends StatefulWidget {
  const _MediaCategoryHideDialog({
    required this.episodes,
    required this.maxWidth,
  });

  final List<MediaLibraryEpisode> episodes;
  final double maxWidth;

  @override
  State<_MediaCategoryHideDialog> createState() =>
      _MediaCategoryHideDialogState();
}

class _MediaCategoryHideDialogState extends State<_MediaCategoryHideDialog> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: FocusTraversalGroup(
        key: const ValueKey<String>('media-category-dialog-focus-group'),
        child: AlertDialog(
          key: const ValueKey<String>('media-category-hide-dialog'),
          title: const Text('选择要隐藏的视频'),
          content: SizedBox(
            width: widget.maxWidth,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('隐藏只影响海报墙，不会删除网盘文件。'),
                  ),
                  for (final episode in widget.episodes)
                    CheckboxListTile(
                      key: ValueKey<String>(
                        'media-category-hide-${episode.stableId}',
                      ),
                      value: _selectedIds.contains(episode.stableId),
                      title: Text(episode.name),
                      subtitle: Text(episode.remotePath ?? ''),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedIds.add(episode.stableId);
                          } else {
                            _selectedIds.remove(episode.stableId);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                        widget.episodes
                            .where(
                              (episode) =>
                                  _selectedIds.contains(episode.stableId),
                            )
                            .toList(growable: false),
                      ),
              child: const Text('隐藏所选'),
            ),
          ],
        ),
      ),
    );
  }
}
