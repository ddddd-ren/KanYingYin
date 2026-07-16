import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/local_directory_picker.dart';
import 'package:kanyingyin/pages/local/library_sheet.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/pages/local/tmdb_scrape_options_sheet.dart';
import 'package:kanyingyin/services/local_custom_cover_service.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:path/path.dart' as p;

class LocalPage extends StatefulWidget {
  const LocalPage({super.key});

  @override
  State<LocalPage> createState() => _LocalPageState();
}

enum _MediaSourceMenuAction { open, remove, removeUnavailable }

class _MediaSourceMenuSelection {
  const _MediaSourceMenuSelection({
    this.source,
    required this.action,
  });

  final LocalMediaSource? source;
  final _MediaSourceMenuAction action;
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
      autoLoadSubtitle: GStorage.setting.get(
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
      autoLoadSubtitle: GStorage.setting.get(
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
              remotePath: item.remotePath!,
              stableId: item.stableId,
              title: item.name,
              subtitleRemotePath: item.subtitleRemotePaths.firstOrNull,
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
    await localController.matchWithBangumi();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(localController.bangumiMatchProgress),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _fetchPosters(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await localController.fetchPosters();
    if (!mounted) return;
    final success = result['success'] ?? 0;
    final failed = result['failed'] ?? 0;
    final skipped = result['skipped'] ?? 0;
    final total = result['total'] ?? 0;
    final msg = total == 0
        ? '当前目录没有需要刮削的视频'
        : success == 0 && failed == 0
            ? '当前目录的视频都已有海报'
            : '刮削完成：成功 $success，失败 $failed，跳过 $skipped';
    messenger.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
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
    final selected = await FilePicker.platform.pickFiles(
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
                  _scrapeTmdbForGroup(pageContext, group);
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
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(
                    ClipboardData(text: firstEpisode.path),
                  );
                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('路径已复制'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _scrapeTmdbForGroup(
    BuildContext context,
    LocalVideoGroup group,
  ) async {
    final seriesName = localController.indexedSeriesNameForPaths(
      group.episodes.map((item) => item.path),
    );
    if (seriesName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先扫描媒体库，再进行 TMDB 刮削')),
      );
      return;
    }

    final options = await showModalBottomSheet<TmdbScrapeOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TmdbScrapeOptionsSheet(
        initialOptions: localController.tmdbScrapeOptions,
      ),
    );
    if (options == null || !context.mounted) return;

    final result = await localController.scrapeSeriesWithTmdb(
      seriesName,
      force: true,
      options: options,
    );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
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
        seriesName: seriesName,
        candidates: result.candidates,
      ),
    );
    if (selected == null || !context.mounted) return;
    final selectedResult = await localController.selectTmdbCandidate(
      seriesName,
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 路径导航栏
            _buildPathBar(context, colorScheme, textTheme),
            // 排序栏
            _buildSortBar(context, colorScheme),
            _buildSearchBar(context, colorScheme),
            // 文件列表
            _buildFileGrid(context, colorScheme, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildPathBar(
      BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Observer(
        builder: (_) {
          return Row(
            children: [
              IconButton(
                icon: const Icon(Icons.folder_open, size: 20),
                tooltip: '选择目录',
                onPressed: localController.isLoading ? null : _pickDirectory,
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 4),
              _buildMediaSourceMenu(context, colorScheme),
              const SizedBox(width: 4),
              IconButton(
                icon: localController.isIndexingLibrary
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.manage_search_outlined, size: 20),
                tooltip: '扫描媒体库',
                onPressed: (localController.isLoading ||
                        localController.isIndexingLibrary ||
                        localController.mediaSources.isEmpty)
                    ? null
                    : () => _refreshLocalLibraryIndex(context),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.video_collection_outlined, size: 20),
                tooltip: '媒体库',
                onPressed: localController.mediaLibraryVideoCount == 0
                    ? null
                    : () => _showLocalLibrary(context),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: '最近目录',
                icon: const Icon(Icons.history, size: 20),
                enabled: !localController.isLoading &&
                    localController.pathHistory.isNotEmpty,
                onSelected: _enterDirectory,
                itemBuilder: (context) {
                  return [
                    for (final path in localController.pathHistory)
                      PopupMenuItem(
                        value: path,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                p.basename(path).isEmpty
                                    ? path
                                    : p.basename(path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: colorScheme.outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ];
                },
              ),
              const SizedBox(width: 4),
              // 返回上级
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 20),
                tooltip: '上级目录',
                onPressed: localController.isLoading ||
                        localController.currentPath.isEmpty
                    ? null
                    : () => localController.navigateUp(),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 4),
              // 刷新
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: '刷新',
                onPressed: localController.isLoading
                    ? null
                    : () => localController.refresh(),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 4),
              // 获取海报
              IconButton(
                icon: localController.isFetchingPosters
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_search, size: 20),
                tooltip: '获取海报',
                onPressed: (localController.isLoading ||
                        localController.isFetchingPosters)
                    ? null
                    : () => _fetchPosters(context),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: localController.isFetchingMediaInfo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.info_outline, size: 20),
                tooltip: '读取媒体信息',
                onPressed: (localController.isLoading ||
                        localController.isFetchingMediaInfo ||
                        localController.currentPath.isEmpty)
                    ? null
                    : () => _fetchMediaInfo(context),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: localController.isFetchingThumbnails
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera_outlined, size: 20),
                tooltip: '生成缩略图',
                onPressed: (localController.isLoading ||
                        localController.isFetchingThumbnails ||
                        localController.currentPath.isEmpty)
                    ? null
                    : () => _fetchThumbnails(context),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: localController.isMatchingBangumi
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined, size: 20),
                tooltip: '批量刮削 TMDB 信息',
                onPressed: (localController.isLoading ||
                        localController.isMatchingBangumi ||
                        localController.localLibraryVideoCount == 0)
                    ? null
                    : () => _scrapeTmdb(context),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 8),
              // 路径面包屑
              Expanded(
                child: _buildBreadcrumb(context, colorScheme, textTheme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBreadcrumb(
      BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    final parts = _splitPath(localController.currentPath);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < parts.length; i++) ...[
            if (i > 0)
              Icon(Icons.chevron_right, size: 16, color: colorScheme.outline),
            GestureDetector(
              onTap: () {
                if (i < parts.length - 1) {
                  final targetPath = _buildPathFromParts(parts, i);
                  _enterDirectory(targetPath);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  _breadcrumbLabel(parts[i]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: i == parts.length - 1
                        ? colorScheme.onSurface
                        : colorScheme.primary,
                    fontWeight: i == parts.length - 1
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMediaSourceMenu(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final sources = localController.mediaSources;
    return PopupMenuButton<_MediaSourceMenuSelection>(
      tooltip: '媒体源',
      icon: const Icon(Icons.video_library_outlined, size: 20),
      enabled: !localController.isLoading && sources.isNotEmpty,
      onSelected: (selection) {
        switch (selection.action) {
          case _MediaSourceMenuAction.open:
            final source = selection.source;
            if (source != null) {
              _enterDirectory(source.path);
            }
          case _MediaSourceMenuAction.remove:
            final source = selection.source;
            if (source != null) {
              _confirmRemoveMediaSource(source);
            }
          case _MediaSourceMenuAction.removeUnavailable:
            _confirmRemoveUnavailableMediaSources();
        }
      },
      itemBuilder: (context) {
        final entries = <PopupMenuEntry<_MediaSourceMenuSelection>>[];
        final unavailableCount = localController.unavailableMediaSourceCount();
        if (unavailableCount > 0) {
          entries
            ..add(
              PopupMenuItem(
                value: const _MediaSourceMenuSelection(
                  action: _MediaSourceMenuAction.removeUnavailable,
                ),
                child: _buildRemoveUnavailableMediaSourceMenuItem(
                  context,
                  colorScheme,
                  unavailableCount,
                ),
              ),
            )
            ..add(const PopupMenuDivider(height: 6));
        }
        for (var i = 0; i < sources.length; i++) {
          final source = sources[i];
          final isAvailable = localController.isMediaSourceAvailable(source);
          entries
            ..add(
              PopupMenuItem(
                enabled: isAvailable,
                value: _MediaSourceMenuSelection(
                  source: source,
                  action: _MediaSourceMenuAction.open,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildMediaSourceMenuItem(
                    context,
                    colorScheme,
                    source,
                  ),
                ),
              ),
            )
            ..add(
              PopupMenuItem(
                value: _MediaSourceMenuSelection(
                  source: source,
                  action: _MediaSourceMenuAction.remove,
                ),
                child: _buildRemoveMediaSourceMenuItem(
                  context,
                  colorScheme,
                  source,
                ),
              ),
            );
          if (i < sources.length - 1) {
            entries.add(const PopupMenuDivider(height: 6));
          }
        }
        return entries;
      },
    );
  }

  Widget _buildMediaSourceMenuItem(
    BuildContext context,
    ColorScheme colorScheme,
    LocalMediaSource source,
  ) {
    final isCurrent = source.path == localController.currentPath;
    final isAvailable = localController.isMediaSourceAvailable(source);
    final iconColor = !isAvailable
        ? colorScheme.error
        : isCurrent
            ? colorScheme.primary
            : colorScheme.outline;
    return Row(
      children: [
        Icon(
          !isAvailable
              ? Icons.error_outline
              : isCurrent
                  ? Icons.check_circle_outline
                  : Icons.folder_outlined,
          size: 20,
          color: iconColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.normal,
                      color: isAvailable ? null : colorScheme.error,
                    ),
              ),
              Text(
                source.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colorScheme.outline),
              ),
              Text(
                _buildMediaSourceSubtitle(source),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: colorScheme.outline),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRemoveMediaSourceMenuItem(
    BuildContext context,
    ColorScheme colorScheme,
    LocalMediaSource source,
  ) {
    return Row(
      children: [
        Icon(Icons.delete_outline, size: 20, color: colorScheme.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '移除“${source.name}”',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colorScheme.error),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoveUnavailableMediaSourceMenuItem(
    BuildContext context,
    ColorScheme colorScheme,
    int count,
  ) {
    return Row(
      children: [
        Icon(Icons.cleaning_services_outlined,
            size: 20, color: colorScheme.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '清理 $count 个失效媒体源',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colorScheme.error),
          ),
        ),
      ],
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

  /// 将路径拆分为 Windows 面包屑段
  /// 例: C:\Users\Videos => [C:, Users, Videos]
  List<String> _splitPath(String path) {
    if (path.isEmpty) return [];
    return p.split(path);
  }

  String _buildPathFromParts(List<String> parts, int index) {
    return p.joinAll(parts.take(index + 1));
  }

  String _breadcrumbLabel(String part) {
    if (part == p.separator) {
      return p.separator;
    }
    return part.endsWith(p.separator)
        ? part.substring(0, part.length - 1)
        : part;
  }

  Widget _buildSortBar(BuildContext context, ColorScheme colorScheme) {
    return Observer(
      builder: (_) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(child: _buildDirectoryStatus(context, colorScheme)),
              _sortChip(context, '名称', 'name'),
              const SizedBox(width: 4),
              _sortChip(context, '大小', 'size'),
              const SizedBox(width: 4),
              _sortChip(context, '日期', 'modified'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索当前目录',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _searchKeyword.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchKeyword = '';
                      });
                    },
                  ),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          onChanged: (value) {
            setState(() {
              _searchKeyword = value.trim().toLowerCase();
            });
          },
        ),
      ),
    );
  }

  Widget _sortChip(BuildContext context, String label, String field) {
    return Observer(
      builder: (_) {
        final isActive = localController.sortBy == field;
        return GestureDetector(
          onTap: () => localController.toggleSort(field),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isActive
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isActive
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.outline,
                      ),
                ),
                if (isActive)
                  Icon(
                    localController.sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 12,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDirectoryStatus(BuildContext context, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    if (localController.isIndexingLibrary) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    localController.libraryIndexProgress.isEmpty
                        ? '正在扫描媒体库'
                        : localController.libraryIndexProgress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${(localController.libraryIndexProgressValue * 100).clamp(0, 100).round()}%',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
                IconButton(
                  tooltip: '取消扫描',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: localController.cancelLocalLibraryIndex,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: localController.libraryIndexTotal > 0
                    ? localController.libraryIndexProgressValue.clamp(0, 1)
                    : null,
                minHeight: 3,
              ),
            ),
            if (localController.libraryIndexCurrentFile.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                localController.libraryIndexCurrentFile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (localController.libraryIndexFailures.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: colorScheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${localController.libraryIndexFailures.length} 项扫描失败',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _showLibraryFailures(context),
              child: const Text('查看'),
            ),
          ],
        ),
      );
    }

    if (localController.isMatchingBangumi) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                localController.bangumiMatchProgress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (localController.bangumiMatchTotal > 0)
              Text(
                '\${localController.bangumiMatchCurrent}/\${localController.bangumiMatchTotal}',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
          ],
        ),
      );
    }

    if (localController.isFetchingPosters) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    localController.posterProgress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (localController.posterTotal > 0)
                  Text(
                    '${(localController.posterProgressValue * 100).clamp(0, 100).round()}%',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: localController.posterTotal > 0
                    ? localController.posterProgressValue.clamp(0, 1)
                    : null,
                minHeight: 3,
              ),
            ),
            if (localController.posterCurrentFile.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                localController.posterCurrentFile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (localController.isFetchingMediaInfo) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                localController.mediaInfoCurrentFile.isEmpty
                    ? '正在读取媒体信息'
                    : localController.mediaInfoCurrentFile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (localController.mediaInfoTotal > 0)
              Text(
                '${localController.mediaInfoCurrent}/${localController.mediaInfoTotal}',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
          ],
        ),
      );
    }

    if (localController.isFetchingThumbnails) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                localController.thumbnailCurrentFile.isEmpty
                    ? '正在生成缩略图'
                    : localController.thumbnailCurrentFile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (localController.thumbnailTotal > 0)
              Text(
                '${localController.thumbnailCurrent}/${localController.thumbnailTotal}',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
          ],
        ),
      );
    }

    if (localController.isLoading) {
      return Text(
        '加载中...',
        style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
      );
    }

    final visibleGroups = _visibleGroups(localController.items);
    final videoCount = visibleGroups.fold<int>(
        0, (count, group) => count + group.episodeCount);
    final searchSuffix = _searchKeyword.isEmpty ? '' : ' · 已筛选';
    final seriesCount = visibleGroups.length;
    final librarySuffix = localController.localLibraryVideoCount == 0
        ? ''
        : ' · 媒体库 ${localController.localLibraryVideoCount} 个视频/${localController.localLibrarySeriesCount} 个系列';
    return Text(
      '$seriesCount 部剧/$videoCount 个视频$searchSuffix$librarySuffix',
      style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
    );
  }

  Widget _buildFileGrid(
      BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    return Expanded(
      child: Observer(
        builder: (_) {
          if (localController.isLoading && localController.items.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (localController.errorMessage != null &&
              localController.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      localController.errorMessage!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => localController.refresh(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }

          final visibleGroups = _visibleGroups(localController.items);
          final tmdbPosterUrls = <LocalVideoGroup, String?>{
            for (final group in visibleGroups)
              group: localController.tmdbPosterUrlForPaths(
                group.episodes.map((item) => item.path),
              ),
          };

          if (localController.items.isEmpty) {
            // 未设置路径：引导用户去设置
            if (localController.currentPath.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_open,
                          size: 48, color: colorScheme.outline),
                      const SizedBox(height: 12),
                      Text(
                        '请先设置本地文件目录',
                        style: textTheme.bodyLarge
                            ?.copyWith(color: colorScheme.outline),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '设置 → 界面 → 本地文件默认路径',
                        style: textTheme.bodySmall
                            ?.copyWith(color: colorScheme.outline),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _pickDirectory,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择文件夹'),
                      ),
                    ],
                  ),
                ),
              );
            }
            // 已设置路径但没有可识别的视频
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.video_file_outlined,
                      size: 48, color: colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(
                    '没有可识别的视频',
                    style: textTheme.bodyLarge
                        ?.copyWith(color: colorScheme.outline),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '仅显示大于 800MB 的视频文件',
                    style: textTheme.bodySmall
                        ?.copyWith(color: colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _pickDirectory,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('切换文件夹'),
                  ),
                ],
              ),
            );
          }

          if (visibleGroups.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 48, color: colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(
                    '没有匹配的文件',
                    style: textTheme.bodyLarge
                        ?.copyWith(color: colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchKeyword = '';
                      });
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('清空搜索'),
                  ),
                ],
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = _getGridCrossAxisCount(context);
              final spacing = _getGridSpacing(context);
              final padding = _getGridPadding(context);
              final mainAxisExtent = _getGridMainAxisExtent(
                context,
                constraints.maxWidth,
                crossAxisCount,
                spacing,
                padding,
              );
              return GridView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(padding),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: 0.68,
                  mainAxisExtent: mainAxisExtent,
                ),
                itemCount: visibleGroups.length,
                itemBuilder: (context, index) {
                  final group = visibleGroups[index];
                  return _buildGroupTile(
                    context,
                    group,
                    colorScheme,
                    textTheme,
                    tmdbPosterUrl: tmdbPosterUrls[group],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  int _getGridCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (Utils.isDesktop()) {
      if (width < 900) return 3;
      return 4;
    }
    if (Utils.isTablet()) return 4;
    return 3; // 手机
  }

  double _getGridSpacing(BuildContext context) {
    return Utils.isDesktop() ? 12 : 8;
  }

  double _getGridPadding(BuildContext context) {
    return Utils.isDesktop() ? 12 : 8;
  }

  double? _getGridMainAxisExtent(
    BuildContext context,
    double maxWidth,
    int crossAxisCount,
    double spacing,
    double padding,
  ) {
    if (!Utils.isDesktop() ||
        !maxWidth.isFinite ||
        maxWidth <= 0 ||
        crossAxisCount <= 0) {
      return null;
    }
    final availableWidth =
        maxWidth - padding * 2 - spacing * (crossAxisCount - 1);
    final itemWidth = availableWidth / crossAxisCount;
    return (itemWidth / 0.68).clamp(320.0, 680.0);
  }

  List<LocalVideoGroup> _visibleGroups(Iterable<LocalFileItem> items) {
    final groups = _seriesGrouper.group(items);
    if (_searchKeyword.isEmpty) {
      return groups;
    }
    return groups.where((group) => group.matches(_searchKeyword)).toList();
  }

  Widget _buildGroupTile(
    BuildContext context,
    LocalVideoGroup group,
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required String? tmdbPosterUrl,
  }) {
    final firstEpisode = group.firstEpisode;
    final cover = group.cover;
    final isScrapingCurrent = localController.isFetchingPosters &&
        (localController.posterCurrentFile == group.title ||
            group.episodes
                .any((item) => localController.posterCurrentFile == item.name));
    var isHovered = false;
    return StatefulBuilder(
      builder: (context, setTileState) {
        final showOverlay = isHovered;
        return MouseRegion(
          onEnter: (_) => setTileState(() => isHovered = true),
          onExit: (_) => setTileState(() => isHovered = false),
          child: Material(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.hardEdge,
            child: InkWell(
              onLongPress: () => _showGroupActions(context, group),
              onSecondaryTap: () => _showGroupActions(context, group),
              onTap: () => _playGroup(group),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildGroupCover(
                    group,
                    colorScheme,
                    cover: cover,
                    tmdbPosterUrl: tmdbPosterUrl,
                  ),
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: showOverlay ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      child: _buildGroupPosterOverlay(
                        context,
                        group,
                        firstEpisode,
                        textTheme,
                        isScrapingCurrent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupCover(
    LocalVideoGroup group,
    ColorScheme colorScheme, {
    required String? cover,
    required String? tmdbPosterUrl,
  }) {
    Widget localCover() {
      if (cover == null || cover.isEmpty) {
        return _buildPosterPlaceholder(group, colorScheme);
      }
      return Image.file(
        File(cover),
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) =>
            _buildPosterPlaceholder(group, colorScheme),
      );
    }

    if (tmdbPosterUrl == null || tmdbPosterUrl.isEmpty) {
      return localCover();
    }
    return Image.network(
      tmdbPosterUrl,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => localCover(),
    );
  }

  Widget _buildPosterPlaceholder(
    LocalVideoGroup group,
    ColorScheme colorScheme,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.82),
      ),
      child: Center(
        child: Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(
            group.hasMultipleEpisodes
                ? Icons.video_collection_outlined
                : Icons.play_circle_fill,
            size: 48,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupPosterOverlay(
    BuildContext context,
    LocalVideoGroup group,
    LocalFileItem firstEpisode,
    TextTheme textTheme,
    bool isScrapingCurrent,
  ) {
    final hasSubtitle = group.episodes.any((item) => item.hasSubtitle);
    final scrapeLabel = isScrapingCurrent
        ? '正在刮削'
        : group.needsOnlinePoster
            ? '未刮削'
            : '已刮削';
    final infoText = group.hasMultipleEpisodes
        ? _buildSeriesInfoText(group)
        : _buildItemInfoText(firstEpisode);
    final mediaInfoText =
        firstEpisode.hasMediaInfo && !group.hasMultipleEpisodes
            ? _buildMediaInfoText(firstEpisode)
            : '';

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.2),
            Colors.black.withValues(alpha: 0.82),
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              group.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              group.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                infoText,
                if (mediaInfoText.isNotEmpty) mediaInfoText,
                _latestModifiedText(group),
              ].where((part) => part.isNotEmpty).join('  ·  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildPosterInfoChip(
                  context,
                  Icons.closed_caption_outlined,
                  hasSubtitle ? '有字幕' : '无字幕',
                ),
                _buildPosterInfoChip(
                  context,
                  Icons.image_search_outlined,
                  scrapeLabel,
                  loading: isScrapingCurrent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterInfoChip(
    BuildContext context,
    IconData icon,
    String label, {
    bool loading = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Colors.white,
                ),
              )
            else
              Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
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
class _BangumiSummaryBlock extends StatefulWidget {
  const _BangumiSummaryBlock({required this.summary});
  final String summary;

  @override
  State<_BangumiSummaryBlock> createState() => _BangumiSummaryBlockState();
}

class _BangumiSummaryBlockState extends State<_BangumiSummaryBlock> {
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
