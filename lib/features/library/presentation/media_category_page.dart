import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';

class MediaCategoryPage extends StatefulWidget {
  const MediaCategoryPage({
    super.key,
    required this.category,
    required this.initialize,
    required this.libraryProvider,
    required this.onPlayEpisode,
    this.observeLibrary = true,
  });

  final MediaLibraryCategory category;
  final Future<void> Function() initialize;
  final MediaCategoryLibraryProvider libraryProvider;
  final MediaCategoryEpisodeAction onPlayEpisode;
  final bool observeLibrary;

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
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: series.length,
      itemBuilder: (context, index) => _seriesCard(context, series[index]),
    );
  }

  Widget _seriesCard(BuildContext context, MediaLibrarySeries series) {
    final details = <String>[
      if (series.tmdbRating != null)
        '${series.tmdbRating!.toStringAsFixed(1)} ★',
      series.episodes.length == 1 ? '1 个视频' : '${series.episodes.length} 集',
    ];
    return ImmersiveMediaCard(
      key: ValueKey<String>('media-category-card-${series.key}'),
      cover: _cover(context, series),
      title: series.title,
      subtitle: series.sourceName,
      details: details.join('  ·  '),
      overlayMode: ImmersiveMediaCardOverlayMode.hover,
      badges: <ImmersiveMediaCardBadge>[
        ImmersiveMediaCardBadge(
          icon: series.sourceKind == MediaSourceKind.local
              ? Icons.storage_outlined
              : Icons.cloud_outlined,
          label: series.isAvailable ? series.sourceName : '来源不可用',
        ),
        ImmersiveMediaCardBadge(
          icon: _categoryIcon(),
          label: widget.category.label,
        ),
      ],
      onTap: !series.isAvailable || _playing ? null : () => _openSeries(series),
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

  Widget _networkCover(
    MediaLibrarySeries series,
    Widget Function() placeholder,
  ) {
    final url = _tmdbImageUrl(series.tmdbPosterUrl);
    if (url == null) return placeholder();
    return Image.network(
      url,
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
                    return ListTile(
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text(
                        episode.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        episode.sourceKind == MediaSourceKind.local
                            ? episode.localItem?.path ?? ''
                            : episode.remotePath ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(episode),
                    );
                  },
                ),
              ),
            ],
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
