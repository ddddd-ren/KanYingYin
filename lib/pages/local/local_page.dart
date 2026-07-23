import 'package:file_picker/file_picker.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/features/library/presentation/library_media_grid.dart';
import 'package:kanyingyin/features/library/presentation/library_path_bar.dart';
import 'package:kanyingyin/features/library/presentation/library_source_menu.dart';
import 'package:kanyingyin/pages/tmdb_match_dialog.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/local_directory_picker.dart';
import 'package:kanyingyin/pages/local/library_sheet.dart';
import 'package:kanyingyin/pages/cloud/quark/quark_share_import_action.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/local_custom_cover_service.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scraper.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:path/path.dart' as p;

enum _LocalMediaAction {
  play,
  editTitle,
  customCover,
  scrapeTmdb,
  rematchTmdb,
  findPoster,
  copyPath,
}

class LocalPage extends StatefulWidget {
  const LocalPage({super.key});

  @override
  State<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends State<LocalPage>
    with AutomaticKeepAliveClientMixin {
  final LocalController localController = Modular.get<LocalController>();
  final LocalVideoController localVideoController =
      Modular.get<LocalVideoController>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final LocalSeriesGrouper _seriesGrouper = const LocalSeriesGrouper();
  final CloudPlaybackResolver _cloudPlaybackResolver = CloudPlaybackResolver();
  final CloudPlaybackNavigationCoordinator _cloudPlaybackNavigation =
      CloudPlaybackNavigationCoordinator();
  String _searchKeyword = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    localController.init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _playGroup(LocalVideoGroup group) {
    final firstEpisode = group.firstEpisode;
    AppLogger().i(
      'LocalPage: playing local series: ${group.title} '
      '(${group.episodeCount} episodes)',
    );
    localVideoController.openFilePlayback(
      filePath: firstEpisode.path,
      seriesTitle: group.title,
      directoryFiles: group.playlistFilesForPlayback,
      playlistAlreadyIsolated: true,
      autoLoadSubtitle: GStorage.setting.getTyped<bool>(
        SettingBoxKey.localAutoLoadSubtitle,
        defaultValue: true,
      ),
    );
    Modular.to.pushNamed('/video/');
  }

  void _playLibraryEpisode(
    LocalMediaSeries series,
    LocalMediaIndexItem episode,
  ) {
    final directoryFiles = series.episodes
        .map((item) => {
              'path': item.path,
              'name': item.name,
              'title': _playbackTitle(item),
            })
        .toList(growable: false);
    AppLogger().i(
        'LocalPage: playing library episode: ${episode.path} (${directoryFiles.length} videos in series)');
    localVideoController.openFilePlayback(
      filePath: episode.path,
      seriesTitle: series.displayTitle,
      directoryFiles: directoryFiles,
      playlistAlreadyIsolated: true,
      autoLoadSubtitle: GStorage.setting.getTyped<bool>(
        SettingBoxKey.localAutoLoadSubtitle,
        defaultValue: true,
      ),
    );
    Modular.to.pushNamed('/video/');
  }

  Future<void> _playCloudLibraryEpisode(
    MediaLibrarySeries series,
    MediaLibraryEpisode episode,
  ) async {
    if (!series.isAvailable || !episode.isAvailable) {
      throw StateError('${episode.sourceName} 已离线或禁用');
    }
    final targets = series.episodes
        .map((item) => CloudPlaybackTarget(
              sourceId: item.sourceId,
              remoteId: item.remoteId!,
              remotePath: item.remotePath!,
              stableId: item.stableId,
              title: item.name,
              subtitleRemotePath: item.subtitleRemotePaths.firstOrNull,
              subtitleRemoteId: item.subtitleRemoteRefs.firstOrNull?.id,
            ))
        .toList(growable: false);
    await localVideoController.openCloudPlayback(
      seriesTitle: series.title,
      targets: targets,
      selectedStableId: episode.stableId,
      resolver: _cloudPlaybackResolver.resolve,
    );
  }

  Future<void> _enterDirectory(String path) async {
    await localController.navigateTo(path);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<String?> _submitDirectoryAddress(String rawPath) async {
    final path = normalizeLibraryPathAddress(rawPath);
    if (path.isEmpty) return '请输入文件夹地址';
    try {
      final type = await FileSystemEntity.type(path, followLinks: true);
      if (type == FileSystemEntityType.file) return '请输入文件夹地址';
      if (type != FileSystemEntityType.directory) {
        return '目录不存在或无法访问';
      }
    } on FileSystemException {
      return '目录不存在或无法访问';
    }
    await _enterDirectory(path);
    return localController.currentPath == path ? null : '目录不存在或无法访问';
  }

  String _playbackTitle(LocalMediaIndexItem item) {
    return p.basenameWithoutExtension(item.name);
  }

  Future<void> _pickDirectory() async {
    final result = await LocalDirectoryPickerPage.pick(
      context,
      initialPath: localController.currentPath.isEmpty
          ? null
          : localController.currentPath,
    );
    if (result == null || result.isEmpty) {
      return;
    }
    final selected = await localController.setRootDirectory(result);
    if (!selected) {
      return;
    }
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _confirmRemoveMediaSource(LocalMediaSource source) async {
    if (localController.isLoading || localController.isIndexingLibrary) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('移除媒体源'),
          content: Text(
            '确定要从媒体源列表移除“${source.name}”吗？\n\n这只会移除记录，不会删除本地文件。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final removed = await localController.removeMediaSource(source.path);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(removed ? '已移除媒体源' : '媒体源已不存在'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmRemoveUnavailableMediaSources() async {
    if (localController.isLoading || localController.isIndexingLibrary) return;
    final count = localController.unavailableMediaSourceCount();
    if (count <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清理失效媒体源'),
          content: Text(
            '发现 $count 个目录已经无法访问，确定要从媒体源列表中清理吗？\n\n'
            '这只会移除应用内记录，不会删除本地文件。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清理'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final removedCount = await localController.removeUnavailableMediaSources();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          removedCount > 0 ? '已清理 $removedCount 个失效媒体源' : '没有需要清理的媒体源',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _scrapeTmdb(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await localController.scrapeTmdbMetadata();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(localController.tmdbScrapeProgress),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _fetchPosterForGroup(
    BuildContext context,
    LocalVideoGroup group,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await localController.fetchPosterForItems(group.episodes);
    if (!mounted) return;
    final success = result['success'] ?? 0;
    final failed = result['failed'] ?? 0;
    final skipped = result['skipped'] ?? 0;
    final msg = success > 0
        ? '已为“${group.title}”保存封面'
        : failed > 0
            ? '没有找到“${group.title}”的可用封面'
            : skipped > 0
                ? '这部剧已经有在线封面'
                : '没有需要刮削的视频';
    messenger.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _setCustomCoverForGroup(
    BuildContext context,
    LocalVideoGroup group,
  ) async {
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      dialogTitle: '选择自定义封面',
    );
    final imagePath = selected?.files.singleOrNull?.path;
    if (imagePath == null || imagePath.isEmpty) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final savedPath = await LocalCustomCoverService().saveForVideo(
        videoPath: group.firstEpisode.path,
        imagePath: imagePath,
      );
      if (savedPath == null) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('不支持该图片格式')),
        );
        return;
      }
      await localController.refresh();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('已为“${group.title}”设置自定义封面')),
      );
    } catch (e) {
      AppLogger().w('LocalPage: failed to set custom cover: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('保存自定义封面失败')),
      );
    }
  }

  Future<void> _editGroupTitle(
    BuildContext context,
    LocalVideoGroup group,
  ) async {
    final input = TextEditingController(text: group.title);
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

    final updated = await localController.updateLocalSeriesTitle(
      group.episodes.map((item) => item.path),
      title,
    );
    if (!context.mounted || !updated) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('剧名已更新')),
    );
  }

  Future<void> _fetchMediaInfo(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final updated = await localController.fetchMediaInfo();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(updated == 0 ? '没有更新到媒体信息' : '已更新 $updated 个视频的媒体信息'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _fetchThumbnails(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final updated = await localController.fetchThumbnails();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(updated == 0 ? '没有需要生成的缩略图' : '已生成 $updated 个视频缩略图'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _refreshLocalLibraryIndex(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await localController.refreshLocalLibraryIndex();
    if (!mounted) return;
    final sources = result['sources'] ?? 0;
    final total = result['total'] ?? 0;
    final added = result['added'] ?? 0;
    final updated = result['updated'] ?? 0;
    final removed = result['removed'] ?? 0;
    final skipped = result['skipped'] ?? 0;
    final failed = result['failed'] ?? 0;
    final cancelled = result['cancelled'] == 1;
    final message = sources == 0
        ? '没有可扫描的媒体源'
        : cancelled
            ? '媒体库扫描已取消'
            : '媒体库已更新：$total 个视频，新增 $added，更新 $updated，移除 $removed，跳过 $skipped，失败 $failed';
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _showLibraryFailures(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final failures = localController.libraryIndexFailures;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.error_outline),
                title: Text('扫描失败项 ${failures.length} 个'),
                subtitle: const Text('可检查文件权限、磁盘连接或路径是否仍存在'),
              ),
              for (final failure in failures.take(20))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    failure.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    failure.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (failures.length > 20)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('还有 ${failures.length - 20} 项未显示'),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: localController.isIndexingLibrary
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        localController.retryFailedLocalLibraryIndexItems();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('重新扫描'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showLocalLibrary(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return LibrarySheetContent(
          controller: localController,
          onPlay: (series, episode) {
            Navigator.of(context).pop();
            _playLibraryEpisode(series, episode);
          },
          onRefresh: () => _refreshLocalLibraryIndex(context),
          headerActions: <Widget>[
            QuarkShareImportAction(
              controller: Modular.get<CloudLibraryController>(),
            ),
          ],
          onPlayCloud: (series, episode) async {
            final request = _cloudPlaybackNavigation.tryBegin();
            if (request == null) return;
            try {
              await _playCloudLibraryEpisode(series, episode);
              if (!context.mounted ||
                  !mounted ||
                  !_cloudPlaybackNavigation.isCurrent(request)) {
                return;
              }
              Navigator.of(context).pop();
              Modular.to.pushNamed('/video/');
            } finally {
              _cloudPlaybackNavigation.finish(request);
            }
          },
        );
      },
    );
  }

  Widget _localMediaMenu(BuildContext context, LocalVideoGroup group) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: 0.86),
      shape: const CircleBorder(),
      child: PopupMenuButton<_LocalMediaAction>(
        tooltip: '本地媒体操作',
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (action) async {
          switch (action) {
            case _LocalMediaAction.play:
              _playGroup(group);
              return;
            case _LocalMediaAction.editTitle:
              await _editGroupTitle(context, group);
              return;
            case _LocalMediaAction.customCover:
              await _setCustomCoverForGroup(context, group);
              return;
            case _LocalMediaAction.scrapeTmdb:
              await _openLocalTmdbDialog(context, group, rematch: false);
              return;
            case _LocalMediaAction.rematchTmdb:
              await _openLocalTmdbDialog(context, group, rematch: true);
              return;
            case _LocalMediaAction.findPoster:
              await _fetchPosterForGroup(context, group);
              return;
            case _LocalMediaAction.copyPath:
              await _copyGroupPath(context, group);
              return;
          }
        },
        itemBuilder: (_) => <PopupMenuEntry<_LocalMediaAction>>[
          PopupMenuItem<_LocalMediaAction>(
            value: _LocalMediaAction.play,
            child: Text(group.episodeCount == 1 ? '播放' : '播放剧集'),
          ),
          const PopupMenuItem<_LocalMediaAction>(
            value: _LocalMediaAction.editTitle,
            child: Text('修改剧名'),
          ),
          const PopupMenuItem<_LocalMediaAction>(
            value: _LocalMediaAction.customCover,
            child: Text('自定义封面'),
          ),
          const PopupMenuItem<_LocalMediaAction>(
            value: _LocalMediaAction.scrapeTmdb,
            child: Text('TMDB 刮削'),
          ),
          const PopupMenuItem<_LocalMediaAction>(
            value: _LocalMediaAction.rematchTmdb,
            child: Text('重新匹配'),
          ),
          const PopupMenuItem<_LocalMediaAction>(
            value: _LocalMediaAction.findPoster,
            child: Text('在线查找封面'),
          ),
          const PopupMenuItem<_LocalMediaAction>(
            value: _LocalMediaAction.copyPath,
            child: Text('复制路径'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyGroupPath(
    BuildContext context,
    LocalVideoGroup group,
  ) async {
    await Clipboard.setData(ClipboardData(text: group.firstEpisode.path));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('路径已复制'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showGroupActions(
    BuildContext context,
    LocalVideoGroup group,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final pageContext = context;
    final firstEpisode = group.firstEpisode;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  Icons.video_collection_outlined,
                  color: colorScheme.primary,
                ),
                title: Text(
                  group.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  group.episodeCount == 1
                      ? _buildItemInfoText(firstEpisode, includeModified: true)
                      : '${group.episodeCount} 集 · ${p.dirname(firstEpisode.path)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.play_arrow_outlined),
                title: Text(group.episodeCount == 1 ? '播放' : '播放剧集'),
                onTap: () {
                  Navigator.of(context).pop();
                  _playGroup(group);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('修改剧名'),
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  _editGroupTitle(pageContext, group);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('自定义封面'),
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  _setCustomCoverForGroup(pageContext, group);
                },
              ),
              ListTile(
                leading: const Icon(Icons.movie_filter_outlined),
                title: const Text('TMDB 刮削'),
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  _openLocalTmdbDialog(pageContext, group, rematch: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.find_replace_outlined),
                title: const Text('重新匹配'),
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  _openLocalTmdbDialog(pageContext, group, rematch: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_search_outlined),
                title: const Text('在线查找封面'),
                onTap: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  _fetchPosterForGroup(pageContext, group);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制路径'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _copyGroupPath(pageContext, group);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openLocalTmdbDialog(
    BuildContext context,
    LocalVideoGroup group, {
    required bool rematch,
  }) async {
    final paths =
        group.episodes.map((item) => item.path).toList(growable: false);
    final seriesName = localController.indexedSeriesNameForPaths(
      paths,
    );
    if (seriesName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先扫描媒体库，再进行 TMDB 刮削')),
      );
      return;
    }
    final draft = localController.localTmdbDraftForPaths(
      originalName: group.title,
      paths: paths,
    );
    final result = await showDialog<TmdbScrapeResult>(
      context: context,
      builder: (_) => TmdbMatchDialog<TmdbScrapeResult>(
        title: rematch ? '重新匹配 TMDB' : 'TMDB 刮削',
        safetyText: '仅更新看影音中的资料，不会修改本地文件',
        draft: draft,
        initialOptions: localController.tmdbScrapeOptions,
        onSearch: (request) => localController.searchLocalTmdb(
          seriesName,
          request,
        ),
        onApply: (candidate, options) async {
          final selected = await localController.selectTmdbCandidate(
            seriesName,
            candidate.metadata,
            options: options,
          );
          if (selected.status != TmdbScrapeStatus.matched) {
            throw StateError('保存匹配结果失败');
          }
          return selected;
        },
      ),
    );
    if (!context.mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.posterDownloadFailures > 0
            ? 'TMDB 信息已更新，部分封面下载失败'
            : 'TMDB 信息已更新'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Observer(
                builder: (_) => LibraryPathBar(
                      data: _pathBarData(),
                      sourceMenu: _sourceMenu(),
                      searchController: _searchController,
                      onPickDirectory: _pickDirectory,
                      onRefresh: localController.refresh,
                      onSort: localController.toggleSort,
                      onSearchChanged: (value) => setState(() {
                        _searchKeyword = value.trim().toLowerCase();
                      }),
                      onClearSearch: _clearSearch,
                      onBreadcrumbSelected: _enterDirectory,
                      onScanLibrary: () => _refreshLocalLibraryIndex(context),
                      onOpenLibrary: () => _showLocalLibrary(context),
                      onOpenRecentPath: _enterDirectory,
                      onNavigateUp: localController.navigateUp,
                      onPathSubmitted: _submitDirectoryAddress,
                      onFetchMediaInfo: () => _fetchMediaInfo(context),
                      onGenerateThumbnails: () => _fetchThumbnails(context),
                      onMatchMetadata: () => _scrapeTmdb(context),
                      onCancelScan: localController.cancelLocalLibraryIndex,
                      onShowFailures: () => _showLibraryFailures(context),
                    )),
            Expanded(child: Observer(builder: (_) => _mediaGrid(context))),
          ],
        ),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchKeyword = '');
  }

  LibraryPathBarViewData _pathBarData() {
    final parts = p.split(localController.currentPath);
    return LibraryPathBarViewData(
      currentPath: localController.currentPath,
      breadcrumbs: [
        for (var i = 0; i < parts.length; i++)
          LibraryBreadcrumbViewData(
            label: _breadcrumbLabel(parts[i]),
            path: p.joinAll(parts.take(i + 1)),
            isCurrent: i == parts.length - 1,
          ),
      ],
      recentPaths: [
        for (final path in localController.pathHistory)
          LibraryRecentPathViewData(
            label: p.basename(path).isEmpty ? path : p.basename(path),
            path: path,
          ),
      ],
      sortBy: localController.sortBy,
      sortAscending: localController.sortAscending,
      status: _directoryStatusData(),
      searchKeyword: _searchKeyword,
      isLoading: localController.isLoading,
      isIndexing: localController.isIndexingLibrary,
      isFetchingPosters: localController.isFetchingPosters,
      isFetchingMediaInfo: localController.isFetchingMediaInfo,
      isFetchingThumbnails: localController.isFetchingThumbnails,
      isMatchingMetadata: localController.isScrapingTmdb,
      canScanLibrary: !localController.isLoading &&
          !localController.isIndexingLibrary &&
          localController.mediaSources.isNotEmpty,
      canOpenLibrary: localController.mediaLibraryVideoCount > 0,
      canNavigateUp:
          !localController.isLoading && localController.currentPath.isNotEmpty,
      canReadMediaInfo: !localController.isLoading &&
          !localController.isFetchingMediaInfo &&
          localController.currentPath.isNotEmpty,
      canGenerateThumbnails: !localController.isLoading &&
          !localController.isFetchingThumbnails &&
          localController.currentPath.isNotEmpty,
      canMatchMetadata: !localController.isLoading &&
          !localController.isScrapingTmdb &&
          localController.localLibraryVideoCount > 0,
    );
  }

  Widget _sourceMenu() {
    return LibrarySourceMenu(
      data: LibrarySourceMenuViewData(
        enabled:
            !localController.isLoading && !localController.isIndexingLibrary,
        unavailableCount: localController.unavailableMediaSourceCount(),
        sources: [
          for (final source in localController.mediaSources)
            LibrarySourceViewData(
              id: source.path,
              name: source.name,
              path: source.path,
              subtitle: _buildMediaSourceSubtitle(source),
              isAvailable: localController.isMediaSourceAvailable(source),
              isCurrent: source.path == localController.currentPath,
            )
        ],
      ),
      onOpen: (source) => _enterDirectory(source.path),
      onRemove: (source) {
        final match = localController.mediaSources
            .where((item) => item.path == source.path)
            .firstOrNull;
        if (match != null) {
          return _confirmRemoveMediaSource(match);
        }
      },
      onRemoveUnavailable: _confirmRemoveUnavailableMediaSources,
    );
  }

  LibraryDirectoryStatusViewData _directoryStatusData() {
    if (localController.isIndexingLibrary) {
      return LibraryDirectoryStatusViewData(
        kind: LibraryDirectoryStatusKind.indexing,
        label: localController.libraryIndexProgress.isEmpty
            ? '正在扫描媒体库'
            : localController.libraryIndexProgress,
        currentFile: localController.libraryIndexCurrentFile,
        progress: localController.libraryIndexTotal > 0
            ? localController.libraryIndexProgressValue.clamp(0, 1)
            : null,
        progressLabel:
            '${(localController.libraryIndexProgressValue * 100).clamp(0, 100).round()}%',
      );
    }
    if (localController.libraryIndexFailures.isNotEmpty) {
      return LibraryDirectoryStatusViewData(
          kind: LibraryDirectoryStatusKind.indexFailures,
          label: '${localController.libraryIndexFailures.length} 项扫描失败');
    }
    if (localController.isScrapingTmdb) {
      return LibraryDirectoryStatusViewData.matchingMetadata(
          label: localController.tmdbScrapeProgress,
          current: localController.tmdbScrapeCurrent,
          total: localController.tmdbScrapeTotal);
    }
    if (localController.isFetchingPosters) {
      return LibraryDirectoryStatusViewData(
          kind: LibraryDirectoryStatusKind.fetchingPosters,
          label: localController.posterProgress,
          currentFile: localController.posterCurrentFile,
          progress: localController.posterTotal > 0
              ? localController.posterProgressValue.clamp(0, 1)
              : null,
          progressLabel: localController.posterTotal > 0
              ? '${(localController.posterProgressValue * 100).clamp(0, 100).round()}%'
              : '');
    }
    if (localController.isFetchingMediaInfo) {
      return LibraryDirectoryStatusViewData(
          kind: LibraryDirectoryStatusKind.fetchingMediaInfo,
          label: localController.mediaInfoCurrentFile.isEmpty
              ? '正在读取媒体信息'
              : localController.mediaInfoCurrentFile,
          progressLabel: localController.mediaInfoTotal > 0
              ? '${localController.mediaInfoCurrent}/${localController.mediaInfoTotal}'
              : '');
    }
    if (localController.isFetchingThumbnails) {
      return LibraryDirectoryStatusViewData(
          kind: LibraryDirectoryStatusKind.fetchingThumbnails,
          label: localController.thumbnailCurrentFile.isEmpty
              ? '正在生成缩略图'
              : localController.thumbnailCurrentFile,
          progressLabel: localController.thumbnailTotal > 0
              ? '${localController.thumbnailCurrent}/${localController.thumbnailTotal}'
              : '');
    }
    if (localController.isLoading) {
      return const LibraryDirectoryStatusViewData(
          kind: LibraryDirectoryStatusKind.loading, label: '加载中...');
    }
    final groups = _visibleGroups(localController.items);
    final videos =
        groups.fold<int>(0, (count, group) => count + group.episodeCount);
    final searchSuffix = _searchKeyword.isEmpty ? '' : ' · 已筛选';
    final librarySuffix = localController.localLibraryVideoCount == 0
        ? ''
        : ' · 媒体库 ${localController.localLibraryVideoCount} 个视频/${localController.localLibrarySeriesCount} 个系列';
    return LibraryDirectoryStatusViewData(
        kind: LibraryDirectoryStatusKind.idle,
        label: '${groups.length} 部剧/$videos 个视频$searchSuffix$librarySuffix');
  }

  Widget _mediaGrid(BuildContext context) {
    final groups = _visibleGroups(localController.items);
    final groupById = {
      for (final group in groups) group.firstEpisode.path: group
    };
    return LibraryMediaGrid(
      data: LibraryMediaGridViewData(
        currentPath: localController.currentPath,
        isLoading: localController.isLoading,
        errorMessage: localController.errorMessage,
        hasSearchFilter: _searchKeyword.isNotEmpty &&
            localController.items.isNotEmpty &&
            groups.isEmpty,
        items: [for (final group in groups) _mediaItemData(group)],
      ),
      scrollController: _scrollController,
      onPickDirectory: _pickDirectory,
      onRetry: localController.refresh,
      onClearSearch: _clearSearch,
      trailingBuilder: (context, item) {
        final group = groupById[item.id];
        return group == null
            ? const SizedBox.shrink()
            : _localMediaMenu(context, group);
      },
      onPlay: (item) {
        final group = groupById[item.id];
        if (group != null) _playGroup(group);
      },
      onShowActions: (item) {
        final group = groupById[item.id];
        if (group != null) return _showGroupActions(context, group);
      },
    );
  }

  LibraryMediaItemViewData _mediaItemData(LocalVideoGroup group) {
    final first = group.firstEpisode;
    final isScraping = localController.isFetchingPosters &&
        (localController.posterCurrentFile == group.title ||
            group.episodes
                .any((item) => localController.posterCurrentFile == item.name));
    return LibraryMediaItemViewData(
      id: first.path,
      title: group.title,
      subtitle: group.subtitle,
      infoText: group.hasMultipleEpisodes
          ? _buildSeriesInfoText(group)
          : _buildItemInfoText(first),
      mediaInfoText: first.hasMediaInfo && !group.hasMultipleEpisodes
          ? _buildMediaInfoText(first)
          : '',
      modifiedText: _latestModifiedText(group),
      hasMultipleEpisodes: group.hasMultipleEpisodes,
      hasSubtitle: group.episodes.any((item) => item.hasSubtitle),
      scrapeLabel: isScraping
          ? '正在刮削'
          : group.needsOnlinePoster
              ? '未刮削'
              : '已刮削',
      localCoverPath: group.cover,
      networkCoverUrl: localController
          .tmdbPosterUrlForPaths(group.episodes.map((item) => item.path)),
      isScraping: isScraping,
      preferLocalCover: !group.needsOnlinePoster,
      heroTag: first.path,
    );
  }

  String _buildMediaSourceSubtitle(LocalMediaSource source) {
    if (!localController.isMediaSourceAvailable(source)) {
      return '目录不可访问，可移除这条记录';
    }
    final scanText = source.lastScannedAt == null
        ? '未扫描'
        : '上次扫描 ${_formatSourceScanTime(source.lastScannedAt!)}';
    return '${source.directoryCount} 个文件夹  ${source.videoCount} 个视频  $scanText';
  }

  String _formatSourceScanTime(DateTime time) {
    final local = time.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  String _breadcrumbLabel(String part) {
    if (part == p.separator) {
      return p.separator;
    }
    return part.endsWith(p.separator)
        ? part.substring(0, part.length - 1)
        : part;
  }

  List<LocalVideoGroup> _visibleGroups(Iterable<LocalFileItem> items) {
    final groups = _seriesGrouper.group(items);
    if (_searchKeyword.isEmpty) {
      return groups;
    }
    return groups.where((group) => group.matches(_searchKeyword)).toList();
  }

  String _buildItemInfoText(
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

  String _buildSeriesInfoText(LocalVideoGroup group) {
    final extensions = group.episodes
        .map((item) => item.extension)
        .where((extension) => extension.isNotEmpty)
        .toSet();
    final sizes =
        group.episodes.fold<int>(0, (total, item) => total + item.size);
    final sizeText = _formatBytes(sizes);
    return [
      if (extensions.isNotEmpty) extensions.join('/'),
      sizeText,
    ].where((part) => part.isNotEmpty).join('  ');
  }

  String _latestModifiedText(LocalVideoGroup group) {
    final latest = group.episodes
        .map((item) => item.modified)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${latest.year}-${twoDigits(latest.month)}-${twoDigits(latest.day)}';
  }

  String _formatBytes(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _buildMediaInfoText(LocalFileItem item) {
    final parts = [
      item.formattedDuration,
      item.formattedResolution,
    ].where((part) => part.isNotEmpty);
    return parts.join('  ');
  }
}

/// 可展开的媒体简介区块。
class _MediaSummaryBlock extends StatefulWidget {
  const _MediaSummaryBlock({required this.summary});
  final String summary;

  @override
  State<_MediaSummaryBlock> createState() => _MediaSummaryBlockState();
}

class _MediaSummaryBlockState extends State<_MediaSummaryBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.summary,
            maxLines: _expanded ? null : 2,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
              height: 1.4,
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _expanded ? '收起' : '展开简介',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
