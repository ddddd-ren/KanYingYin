import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/presentation/library_toolbar.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/features/library/application/media_card_info.dart';
import 'package:kanyingyin/features/library/presentation/library_media_grid.dart';
import 'package:kanyingyin/features/library/presentation/media_library_details_dialog.dart';
import 'package:kanyingyin/features/tv/presentation/tv_layout_policy.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';
import 'package:kanyingyin/widgets/poster_cover.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

class MediaCategoryPage extends StatefulWidget {
  const MediaCategoryPage({
    super.key,
    required this.category,
    required this.initialize,
    required this.libraryProvider,
    required this.onPlayEpisode,
    this.refresh,
    this.onHideEpisodes,
    this.observeLibrary = true,
    this.libraryListenable,
    this.capabilities,
    this.userStatesProvider,
    this.onUserStateChanged,
    this.reconcileUserStates,
    this.onRelinkUserState,
    this.watchStatesProvider,
    this.onWatchedChanged,
    this.classificationModeProvider,
    this.onDispose,
  });

  final MediaLibraryCategory category;
  final Future<void> Function() initialize;
  final MediaCategoryLibraryProvider libraryProvider;
  final MediaCategoryEpisodeAction onPlayEpisode;
  final Future<void> Function()? refresh;
  final MediaCategoryHideEpisodesAction? onHideEpisodes;
  final bool observeLibrary;
  final Listenable? libraryListenable;
  final AppPlatformCapabilities? capabilities;
  final Map<String, MediaLibraryUserState> Function()? userStatesProvider;
  final Future<void> Function(String, MediaLibraryUserState)?
      onUserStateChanged;
  final Future<void> Function()? reconcileUserStates;
  final Future<void> Function(String, String)? onRelinkUserState;
  final Map<String, MediaWatchState> Function()? watchStatesProvider;
  final Future<void> Function(List<MediaLibraryEpisode>, bool)?
      onWatchedChanged;
  final MediaClassificationMode Function()? classificationModeProvider;
  final VoidCallback? onDispose;

  @override
  State<MediaCategoryPage> createState() => _MediaCategoryPageState();
}

class _MediaCategoryPageState extends State<MediaCategoryPage> {
  static const MediaLibraryQuery _queryService = MediaLibraryQuery();

  final _searchController = TextEditingController();
  String _sourceId = 'all';
  String _keyword = '';
  bool _loading = true;
  bool _playing = false;
  String? _errorMessage;
  String? _posterWarmupIdentity;
  String? _stateIdentity;
  bool _reconcilingStates = false;

  @override
  void initState() {
    super.initState();
    MediaWatchStateRepository.changes.addListener(_watchChanged);
    _initialize();
  }

  void _watchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    MediaWatchStateRepository.changes.removeListener(_watchChanged);
    _searchController.dispose();
    widget.onDispose?.call();
    super.dispose();
  }

  Future<void> _initialize({bool refresh = false}) async {
    _stateIdentity = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      await (refresh
          ? (widget.refresh ?? widget.initialize)
          : widget.initialize)();
    } on Object {
      _errorMessage = '媒体分类加载失败，请稍后重试';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  CloudMediaLibrary _library() {
    return widget.libraryProvider();
  }

  MediaClassificationMode get _classificationMode =>
      widget.classificationModeProvider?.call() ??
      MediaClassificationMode.conservative;

  @override
  Widget build(BuildContext context) {
    Widget content() => widget.observeLibrary
        ? Observer(builder: (_) => _buildContent())
        : Builder(builder: (_) => _buildContent());
    final listenable = widget.libraryListenable;
    final body = listenable == null
        ? content()
        : ListenableBuilder(
            listenable: listenable,
            builder: (_, __) => content(),
          );
    return Scaffold(
      body: SafeArea(child: body),
    );
  }

  Widget _buildContent() {
    final library = _library();
    _scheduleReconcile(library);
    final sourceId = library.filters.any(
      (filter) => filter.id == _sourceId,
    )
        ? _sourceId
        : 'all';
    final userStates = widget.userStatesProvider?.call() ??
        const <String, MediaLibraryUserState>{};
    final series = _queryService.apply(
      series: library.series,
      sourceId: sourceId,
      keyword: _keyword,
      selectedCategories: <String>{widget.category.label},
      userStates: userStates,
      classificationMode: _classificationMode,
    );
    return Column(
      children: [
        _header(context, library, series.length, sourceId),
        if (widget.onRelinkUserState != null)
          _unlinkedStates(library, userStates),
        Expanded(child: _content(context, series)),
      ],
    );
  }

  void _scheduleReconcile(CloudMediaLibrary library) {
    final callback = widget.reconcileUserStates;
    if (callback == null || _loading || _reconcilingStates) return;
    final identity = library.series
        .map((series) =>
            '${series.key}:${series.episodes.map((e) => e.stableId).join(',')}')
        .join('\n');
    if (_stateIdentity == identity) return;
    _stateIdentity = identity;
    _reconcilingStates = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await callback();
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('媒体状态关联失败，请刷新后重试')),
          );
        }
      } finally {
        _reconcilingStates = false;
        if (mounted) setState(() {});
      }
    });
  }

  Widget _unlinkedStates(
      CloudMediaLibrary library, Map<String, MediaLibraryUserState> states) {
    final keys = library.series.map((series) => series.key).toSet();
    final pending = states.keys.where((key) => !keys.contains(key)).toList();
    if (pending.isEmpty) return const SizedBox.shrink();
    return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.link),
          label: Text('${pending.length} 项收藏/待看记录待关联'),
          onPressed: () => _relinkState(pending, library),
        ));
  }

  Future<void> _relinkState(
      List<String> pending, CloudMediaLibrary library) async {
    final oldKey = await showDialog<String>(
        context: context,
        builder: (context) =>
            SimpleDialog(title: const Text('选择待关联记录'), children: [
              for (final key in pending)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, key),
                  child: Text(key),
                ),
            ]));
    if (oldKey == null || !mounted) return;
    final targetKey = await showDialog<String>(
        context: context,
        builder: (context) =>
            SimpleDialog(title: const Text('关联到当前作品'), children: [
              for (final series in library.series)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, series.key),
                  child: Text(
                      '${series.title} · ${series.sourceName} · ${series.episodes.length} 个视频'),
                ),
            ]));
    if (targetKey == null || !mounted) return;
    try {
      await widget.onRelinkUserState!(oldKey, targetKey);
      if (mounted) setState(() {});
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('关联保存失败，原记录已保留')),
        );
      }
    }
  }

  Widget _header(
    BuildContext context,
    CloudMediaLibrary library,
    int count,
    String sourceId,
  ) {
    final showRefreshProgress = _loading && library.series.isNotEmpty;
    return LibraryToolbar(
      title: widget.category.label,
      titleKey: const ValueKey<String>('media-category-title'),
      icon: _categoryIcon(),
      count: count,
      searchController: _searchController,
      searchKey: const ValueKey<String>('media-category-search'),
      searchHint: '搜索${widget.category.label}',
      onSearchChanged: (value) => setState(() => _keyword = value.trim()),
      onClearSearch: () => setState(() {
        _searchController.clear();
        _keyword = '';
      }),
      leading: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey<String>('media-category-source-filter'),
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
            if (value != null) {
              setState(() => _sourceId = value);
            }
          },
        ),
      ),
      actions: [
        IconButton(
          tooltip: '刷新分类',
          onPressed: _loading ? null : () => _initialize(refresh: true),
          icon: showRefreshProgress
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    List<MediaLibrarySeries> series,
  ) {
    if (_loading && series.isEmpty) {
      return MediaCardSkeletonGrid(
        capabilities: widget.capabilities,
        fallbackMaxCrossAxisExtent: 280,
      );
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
            Text(_keyword.isNotEmpty
                ? '没有匹配的作品'
                : '还没有${widget.category.label}'),
            if (_keyword.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  _searchController.clear();
                  _keyword = '';
                }),
                child: const Text('清除搜索'),
              ),
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
          fallbackChildAspectRatio: posterAspectRatio,
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
      userState: _userState(series),
      classificationMode: _classificationMode,
    );
    return ImmersiveMediaCard(
      key: ValueKey<String>('media-category-card-${series.key}'),
      cover: _cover(series),
      title: info.title,
      subtitle: info.subtitle,
      details: info.details,
      capabilities: widget.capabilities ?? detectAppPlatform(),
      overlayMode: ImmersiveMediaCardOverlayMode.hover,
      badges: info.badges,
      technicalBadges: info.technicalBadges,
      trailing: _seriesMenu(series),
      watchProgress: widget.watchStatesProvider == null
          ? null
          : mediaSeriesProgress(series, widget.watchStatesProvider!()),
      onTap: !series.isAvailable || _playing
          ? null
          : () => _openSeriesFromCard(series),
    );
  }

  Future<void> _openSeriesFromCard(MediaLibrarySeries series) {
    final platform = widget.capabilities ?? detectAppPlatform();
    if (platform.isAndroid && !platform.isAndroidTv) {
      var currentSeries = series;
      return showMediaLibraryDetailsDialog(
        context: context,
        series: series,
        seriesProvider: () => currentSeries = _currentSeries(currentSeries),
        libraryListenable: widget.libraryListenable,
        observeLibrary: widget.observeLibrary,
        capabilities: platform,
        onPlay: series.isAvailable && !_playing
            ? () => _openSeries(currentSeries)
            : null,
      );
    }
    return _openSeries(series);
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
          if (widget.onWatchedChanged != null)
            PopupMenuItem(
                value: _MediaCategoryAction.watched,
                child: Text(mediaSeriesWatched(
                        series, widget.watchStatesProvider?.call() ?? const {})
                    ? '标记未看'
                    : '标记已看')),
          PopupMenuItem<_MediaCategoryAction>(
            value: _MediaCategoryAction.favorite,
            child: Text(_userState(series).favorite ? '取消收藏' : '收藏'),
          ),
          PopupMenuItem<_MediaCategoryAction>(
            value: _MediaCategoryAction.watchLater,
            child: Text(
              _userState(series).watchLater ? '移出待看' : '加入待看',
            ),
          ),
          const PopupMenuItem<_MediaCategoryAction>(
            value: _MediaCategoryAction.collections,
            child: Text('管理合集'),
          ),
          const PopupMenuDivider(),
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
      case _MediaCategoryAction.watched:
        try {
          await widget.onWatchedChanged?.call(
              series.episodes,
              !mediaSeriesWatched(
                  series, widget.watchStatesProvider?.call() ?? const {}));
          if (mounted) setState(() {});
        } on Object {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已看状态保存失败，请重试')));
          }
        }
        return;
      case _MediaCategoryAction.favorite:
        await _saveUserState(
          series,
          _userState(series).copyWith(
            favorite: !_userState(series).favorite,
            updatedAt: DateTime.now(),
          ),
        );
        return;
      case _MediaCategoryAction.watchLater:
        await _saveUserState(
          series,
          _userState(series).copyWith(
            watchLater: !_userState(series).watchLater,
            updatedAt: DateTime.now(),
          ),
        );
        return;
      case _MediaCategoryAction.collections:
        await _editCollections(series);
        return;
      case _MediaCategoryAction.play:
        await _openSeries(series);
        return;
      case _MediaCategoryAction.details:
        await _showSeriesDetails(series);
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

  MediaLibraryUserState _userState(MediaLibrarySeries series) {
    return widget.userStatesProvider?.call()[series.key] ??
        MediaLibraryUserState.empty;
  }

  Future<void> _showSeriesDetails(MediaLibrarySeries series) {
    var currentSeries = series;
    return showMediaLibraryDetailsDialog(
      context: context,
      series: series,
      seriesProvider: () => currentSeries = _currentSeries(currentSeries),
      libraryListenable: widget.libraryListenable,
      observeLibrary: widget.observeLibrary,
      capabilities: widget.capabilities,
      onPlay: series.isAvailable && !_playing
          ? () => _openSeries(currentSeries)
          : null,
    );
  }

  Future<void> _saveUserState(
    MediaLibrarySeries series,
    MediaLibraryUserState state,
  ) async {
    final callback = widget.onUserStateChanged;
    if (callback == null) return;
    try {
      await callback(series.key, state);
      if (mounted) setState(() {});
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('媒体状态保存失败，请重试')),
      );
    }
  }

  Future<void> _editCollections(MediaLibrarySeries series) async {
    final initial = List<String>.from(_userState(series).collections);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _CollectionEditorDialog(initial: initial),
    );
    if (result == null || !mounted) return;
    await _saveUserState(
      series,
      _userState(series).copyWith(
        collections: result,
        updatedAt: DateTime.now(),
      ),
    );
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

  Widget _cover(MediaLibrarySeries series) {
    if (series.sourceKind == MediaSourceKind.cloud) {
      return CloudPosterImage(
        cachePath: series.posterCachePath,
        url: _tmdbImageUrl(series.tmdbPosterUrl),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return PosterCover(child: _localOrNetworkCover(series));
  }

  Widget _localOrNetworkCover(MediaLibrarySeries series) {
    final cached = series.posterCachePath;
    if (cached != null && cached.isNotEmpty && File(cached).existsSync()) {
      return Image.file(
        File(cached),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _networkCover(series),
      );
    }
    return _networkCover(series);
  }

  void _scheduleCloudPosterWarmup(
    BuildContext context,
    List<MediaLibrarySeries> series,
  ) {
    final limit = cloudPosterWarmupLimit(
      MediaQuery.sizeOf(context),
      maxCrossAxisExtent: 280,
      childAspectRatio: posterAspectRatio,
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

  Widget _networkCover(MediaLibrarySeries series) {
    final url = _tmdbImageUrl(series.tmdbPosterUrl);
    if (url == null) return const PosterCover.placeholder();
    return TmdbNetworkImage(
      url: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const PosterCover.placeholder(),
    );
  }

  MediaLibrarySeries _currentSeries(MediaLibrarySeries original) {
    final ids = original.episodes.map((episode) => episode.stableId).toSet();
    final matches = _library()
        .series
        .where((series) =>
            series.sourceKind == original.sourceKind &&
            series.sourceId == original.sourceId &&
            series.episodes.any((episode) => ids.contains(episode.stableId)))
        .take(2)
        .toList(growable: false);
    return matches.length == 1 ? matches.single : original;
  }

  Future<void> _openSeries(MediaLibrarySeries original) async {
    final series = _currentSeries(original);
    if (series.episodes.isEmpty) return;
    final selection = series.episodes.length == 1
        ? (series: series, episode: series.episodes.single)
        : await _selectEpisode(series);
    if (selection == null || !mounted) return;
    setState(() => _playing = true);
    try {
      await widget.onPlayEpisode(
        _currentSeries(selection.series),
        selection.episode,
      );
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

  Future<({MediaLibrarySeries series, MediaLibraryEpisode episode})?>
      _selectEpisode(MediaLibrarySeries original) {
    var currentSeries = original;
    String? selectedVersionKey = original.versions.firstOrNull?.key;
    return showModalBottomSheet<
        ({MediaLibrarySeries series, MediaLibraryEpisode episode})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, setSheetState) {
        Widget content() {
          final series = currentSeries = _currentSeries(currentSeries);
          final versionIndex = series.versions
              .indexWhere((version) => version.key == selectedVersionKey);
          final selectedVersion = versionIndex < 0 ? 0 : versionIndex;
          final episodes = series.versions.isEmpty
              ? series.episodes
              : series.versions[selectedVersion].episodes;
          return SafeArea(
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
                    if (series.versions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          for (var index = 0;
                              index < series.versions.length;
                              index++)
                            ChoiceChip(
                              label: Text(series.versions[index].label),
                              selected: selectedVersion == index,
                              onSelected: (_) => setSheetState(() =>
                                  selectedVersionKey =
                                      series.versions[index].key),
                            ),
                        ]),
                      ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: episodes.length,
                        itemBuilder: (context, index) {
                          final episode = episodes[index];
                          final local = episode.localItem;
                          final technicalBadges =
                              const MediaTechnicalBadgeResolver().resolve(
                            names: [
                              episode.name,
                              if (local != null) local.path,
                              if (local != null) ...local.originalNames,
                              if (episode.remotePath != null)
                                episode.remotePath!,
                            ],
                            releaseTags: [episode.releaseTags],
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
                                  if (episode.sharedFromVersionLabel != null)
                                    Text(
                                        '共享自${episode.sharedFromVersionLabel}'),
                                ],
                              ),
                              onTap: () => Navigator.of(context).pop(
                                (series: series, episode: episode),
                              ),
                            ),
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

        Widget observed() => widget.observeLibrary
            ? Observer(builder: (_) => content())
            : Builder(builder: (_) => content());
        final listenable = widget.libraryListenable;
        return listenable == null
            ? observed()
            : ListenableBuilder(
                listenable: listenable,
                builder: (_, __) => observed(),
              );
      }),
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

enum _MediaCategoryAction {
  watched,
  favorite,
  watchLater,
  collections,
  play,
  details,
  copyPath,
  hide,
}

class _CollectionEditorDialog extends StatefulWidget {
  const _CollectionEditorDialog({required this.initial});

  final List<String> initial;

  @override
  State<_CollectionEditorDialog> createState() =>
      _CollectionEditorDialogState();
}

class _CollectionEditorDialogState extends State<_CollectionEditorDialog> {
  late final List<String> _collections = List<String>.from(widget.initial);
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final value = _controller.text.trim();
    if (value.isEmpty ||
        value.length > MediaLibraryUserState.maxCollectionLength ||
        _collections.any((item) => item.toLowerCase() == value.toLowerCase()) ||
        _collections.length >= MediaLibraryUserState.maxCollections) {
      return;
    }
    setState(() {
      _collections.add(value);
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理合集'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              maxLength: MediaLibraryUserState.maxCollectionLength,
              decoration: const InputDecoration(
                labelText: '新合集名称',
                suffixIcon: Icon(Icons.add),
              ),
              onSubmitted: (_) => _add(),
            ),
            if (_collections.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final collection in _collections)
                    InputChip(
                      label: Text(collection),
                      onDeleted: () => setState(
                        () => _collections.remove(collection),
                      ),
                    ),
                ],
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
          onPressed: () {
            _add();
            Navigator.of(context).pop(
              MediaLibraryUserState.normalizeCollections(_collections),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

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
