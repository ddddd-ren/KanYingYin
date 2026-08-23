import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/cloud/application/cloud_resources_toolbar.dart';
import 'package:kanyingyin/features/episode_matching/application/cloud_episode_match_service.dart';
import 'package:kanyingyin/features/episode_matching/presentation/manual_episode_match_dialog.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_episode_sheet.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_hidden_video_dialogs.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_playback_request.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_poster_wall.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_media_details_dialog.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_tmdb_match_dialog.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_tag_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/utils/logger.dart';

String cloudPlaybackFailureDiagnostic(
  CloudSource source,
  Object error, {
  AppPlatformCapabilities? capabilities,
}) {
  final platform = capabilities ?? detectAppPlatform();
  final profile = platform.isAndroidTv
      ? 'android_tv_safe'
      : platform.isAndroid
          ? 'android'
          : 'windows';
  return 'CloudResourcesPage: playback failed '
      'provider=${source.type.name} sourceId=${source.id} '
      'stage=resolve-or-load sdk=${platform.androidSdkInt} '
      'profile=$profile errorType=${error.runtimeType}';
}

typedef CloudSourceAddCallback = FutureOr<String?> Function();

class CloudResourcesPage extends StatefulWidget {
  const CloudResourcesPage({
    super.key,
    this.controller,
    this.onAddQuark,
    this.onAddBaidu,
    this.onAddXunlei,
    this.onAddOpenList,
    this.onManageSources,
    this.onPlayRequest,
    this.onDeleteSource,
    this.capabilities,
  });

  final CloudResourcesController? controller;
  final CloudSourceAddCallback? onAddQuark;
  final CloudSourceAddCallback? onAddBaidu;
  final CloudSourceAddCallback? onAddXunlei;
  final CloudSourceAddCallback? onAddOpenList;
  final VoidCallback? onManageSources;
  final FutureOr<void> Function(CloudResourcePlaybackRequest request)?
      onPlayRequest;
  final FutureOr<void> Function(String sourceId)? onDeleteSource;
  final AppPlatformCapabilities? capabilities;

  @override
  State<CloudResourcesPage> createState() => _CloudResourcesPageState();
}

class _CloudResourcesPageState extends State<CloudResourcesPage> {
  late final CloudResourcesController _controller;
  late final AppPlatformCapabilities _capabilities;
  final CloudPlaybackResolver _playbackResolver = CloudPlaybackResolver();
  final CloudPlaybackNavigationCoordinator _playbackNavigation =
      CloudPlaybackNavigationCoordinator();
  final CloudResourcesToolbarPolicy _toolbarPolicy =
      const CloudResourcesToolbarPolicy();
  bool _batchScraping = false;
  int _batchCurrent = 0;
  int _batchTotal = 0;
  bool _autoOrganizing = false;
  CloudResourceAutoOrganizeProgress? _autoOrganizeProgress;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? Modular.get<CloudResourcesController>();
    _capabilities = widget.capabilities ?? detectAppPlatform();
    _controller.addListener(_refresh);
    _controller.load(startScan: !_capabilities.isAndroidTv);
  }

  @override
  void dispose() {
    _playbackNavigation.invalidate();
    _controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _addCloudSource(_CloudAddAction action) async {
    final callback = switch (action) {
      _CloudAddAction.quark => widget.onAddQuark,
      _CloudAddAction.baidu => widget.onAddBaidu,
      _CloudAddAction.xunlei => widget.onAddXunlei,
      _CloudAddAction.openList => widget.onAddOpenList,
    };
    final sourceId = callback != null
        ? await callback()
        : await Modular.to.pushNamed<String>(_routeFor(action));
    if (!mounted || sourceId == null || sourceId.isEmpty) return;
    await _controller.reloadSourcesAndSnapshot(
      preferredSourceId: sourceId,
    );
    if (!mounted || _controller.errorMessage == null) return;
    _showMessage('网盘来源刷新失败，已保留当前媒体库，请重试');
  }

  String _routeFor(_CloudAddAction action) => switch (action) {
        _CloudAddAction.quark => '/settings/cloud-sources/quark/edit',
        _CloudAddAction.baidu => '/settings/cloud-sources/baidu/edit',
        _CloudAddAction.xunlei => '/settings/cloud-sources/xunlei/edit',
        _CloudAddAction.openList => '/settings/cloud-sources/openlist/edit',
      };

  void _manageSources() {
    final callback = widget.onManageSources;
    if (callback != null) {
      callback();
    } else {
      Modular.to.pushNamed('/settings/cloud-sources');
    }
  }

  Future<void> _play(
    CloudResourceMediaGroup group,
    CloudFileEntry entry,
  ) async {
    final source = _controller.selectedSource;
    if (source == null) return;
    final generation = _playbackNavigation.tryBegin();
    if (generation == null) return;
    try {
      final request = buildCloudResourcePlaybackRequest(
        sourceId: source.id,
        group: group,
        selected: entry,
        subtitleFor: _matchingSubtitle,
      );
      final callback = widget.onPlayRequest;
      if (callback != null) {
        await callback(request);
        return;
      }
      await Modular.get<LocalVideoController>().openCloudPlayback(
        seriesTitle: request.seriesTitle,
        targets: request.targets,
        selectedStableId: request.selectedStableId,
        resolver: _playbackResolver.resolve,
      );
      if (!mounted || !_playbackNavigation.isCurrent(generation)) return;
      await Modular.to.pushNamed('/video/');
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        cloudPlaybackFailureDiagnostic(
          source,
          error,
          capabilities: _capabilities,
        ),
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网盘视频解析或加载失败')),
      );
    } finally {
      _playbackNavigation.finish(generation);
    }
  }

  Future<void> _openGroup(CloudResourceMediaGroup group) async {
    if (!group.isSeries && group.videos.length == 1) {
      await _play(group, group.anchor);
      return;
    }
    final source = _controller.selectedSource;
    if (source == null || !mounted) return;
    final selected = await showCloudResourceEpisodeSheet(
      context: context,
      sourceId: source.id,
      group: group,
      subtitleVideoKeys: _subtitleVideoKeys(source.id),
      capabilities: _capabilities,
    );
    if (selected != null && mounted) await _play(group, selected);
  }

  Future<void> _hideVideos(CloudResourceMediaGroup group) async {
    final selected = await showCloudHideVideoDialog(
      context: context,
      videos: group.videos,
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    try {
      await _controller.hideVideos(selected);
      if (mounted) _showMessage('已隐藏 ${selected.length} 个视频');
    } on Object {
      if (mounted) _showMessage('隐藏设置保存失败，请重试');
    }
  }

  CloudRemoteRef? _matchingSubtitle(CloudFileEntry video) =>
      _controller.subtitleFor(video);

  Set<String> _subtitleVideoKeys(String sourceId) => _controller.entries
      .where(_controller.hasSubtitle)
      .map(
        (entry) => cloudResourceTmdbKey(
          sourceId: sourceId,
          remoteId: entry.id,
          remotePath: entry.remotePath,
        ),
      )
      .toSet();

  Future<void> _scrapeEntry(CloudResourceMediaGroup group) async {
    await _openTmdbDialog(group, rematch: false);
  }

  Future<void> _rematchEntry(CloudResourceMediaGroup group) async {
    await _openTmdbDialog(group, rematch: true);
  }

  Future<void> _manualMatchEntry(CloudResourceMediaGroup group) async {
    await _openTmdbDialog(group, rematch: true);
  }

  Future<void> _matchEpisodes(CloudResourceMediaGroup group) async {
    try {
      final entry = group.anchor;
      final workGroup = _isWorkGroup(group);
      final draft = workGroup
          ? _controller.tmdbDraftForGroup(group)
          : _controller.tmdbDraftFor(entry);
      final selected = await showDialog<TmdbMetadata>(
        context: context,
        builder: (_) => TmdbMatchDialog<TmdbMetadata>(
          title: '选择 TMDB 电视剧',
          safetyText: '仅更新看影音中的资料，不会修改网盘文件',
          draft: TmdbMatchDraft(
            originalName: draft.originalName,
            searchTitle: draft.searchTitle,
            mediaTypeMode: TmdbMediaTypeMode.tv,
            year: draft.year,
            seasonNumber: draft.seasonNumber,
            episodeNumber: draft.episodeNumber,
          ),
          initialOptions: _controller.tmdbScrapeOptions.copyWith(
            mediaTypeMode: TmdbMediaTypeMode.tv,
          ),
          onSearch: (request) async {
            final prepared = CloudResourceTmdbSearchRequest(
              queryTitle: request.queryTitle,
              queryYear: request.queryYear,
              mediaTypeMode: TmdbMediaTypeMode.tv,
              options: request.options.copyWith(
                mediaTypeMode: TmdbMediaTypeMode.tv,
              ),
            );
            if (workGroup) {
              return TmdbPreparedSearchOutcome(
                ranked: await _controller.searchWorkTmdb(group, prepared),
              );
            }
            return TmdbPreparedSearchOutcome(
              ranked: (await _controller.searchTmdb(entry, prepared)).ranked,
            );
          },
          onApply: (candidate, _) async {
            if (candidate.metadata.mediaType != TmdbMediaType.tv) {
              throw StateError('请选择电视剧作品');
            }
            return candidate.metadata;
          },
        ),
      );
      if (!mounted || selected == null) return;

      final matchController =
          await _controller.manualEpisodeMatchControllerForGroup(
        group: group,
        selectedSeries: selected,
      );
      if (!mounted) return;
      CloudEpisodeMatchSaveOutcome? saveOutcome;
      var saved = false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ManualEpisodeMatchDialog<void>(
          controller: matchController,
          onSave: (metadata, seasonNumber, assignments) async {
            saveOutcome = await _controller.saveManualEpisodeAssignments(
              group: group,
              assignments: assignments,
              metadata: metadata,
              selectedSeasonNumber: seasonNumber,
            );
            saved = true;
          },
        ),
      );
      if (!mounted || !saved) return;
      _showMessage(saveOutcome?.indexSynced == false
          ? '剧集匹配规则已保存，将在下次扫描时生效'
          : '剧集匹配已保存');
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_manualEpisodeErrorMessage(error));
    }
  }

  Future<void> _openTmdbDialog(
    CloudResourceMediaGroup group, {
    required bool rematch,
  }) async {
    try {
      final entry = group.anchor;
      final workGroup = _isWorkGroup(group);
      final outcome = await showDialog<CloudResourceTmdbSelectionOutcome>(
        context: context,
        builder: (context) => CloudTmdbMatchDialog(
          title: rematch ? '重新匹配 TMDB' : 'TMDB 刮削',
          safetyText: '仅更新看影音中的资料，不会修改网盘文件',
          draft: workGroup
              ? _controller.tmdbDraftForGroup(group)
              : _controller.tmdbDraftFor(entry),
          initialOptions: _controller.tmdbScrapeOptions,
          onSearch: (request) async {
            if (workGroup) {
              return CloudResourceTmdbSearchOutcome(
                ranked: await _controller.searchWorkTmdb(group, request),
              );
            }
            return _controller.searchTmdb(entry, request);
          },
          onApply: (candidate, options) async {
            if (!workGroup) {
              return _controller.applyTmdbCandidate(
                entry,
                candidate,
                options: options,
              );
            }
            final selected = await _controller.applyWorkTmdbCandidate(
              group,
              candidate,
              options: options,
            );
            final metadata = selected.record.metadata!;
            return CloudResourceTmdbSelectionOutcome(
              record: CloudResourceTmdbRecord.matched(
                sourceId: selected.record.sourceId,
                remoteId: entry.id,
                remotePath: entry.remotePath,
                displayName: group.displayName,
                resourceKind: CloudResourceKind.standaloneVideo,
                metadata: metadata,
                checkedAt: selected.record.checkedAt,
                posterCachePath: selected.record.posterCachePath,
              ),
              posterCached: selected.posterCached,
              indexSynced: selected.indexSynced,
            );
          },
        ),
      );
      if (!mounted || outcome == null) return;
      final title = outcome.record.title ?? entry.name;
      final propagation = outcome.seriesPropagation;
      String message;
      if (propagation.eligible && !propagation.ruleSaved) {
        message =
            '已保存“$title”，并匹配 ${propagation.propagatedCount} 个分集，但自动继承规则保存失败';
      } else if (propagation.propagatedCount > 0) {
        message = '已保存“$title”，并自动匹配同目录 ${propagation.propagatedCount} 个分集';
      } else if (!outcome.posterCached && !outcome.indexSynced) {
        message = '已保存“$title”，海报暂未缓存，媒体索引将在下次加载时重试';
      } else if (!outcome.posterCached) {
        message = '已保存“$title”，海报暂未缓存';
      } else if (!outcome.indexSynced) {
        message = '已保存“$title”，媒体索引将在下次加载时重试';
      } else {
        message = '已保存“$title”的匹配信息';
      }
      if (propagation.indexSyncFailures > 0) {
        message =
            '$message，另有 ${propagation.indexSyncFailures} 个分集的媒体索引将在下次加载时重试';
      }
      _showMessage(message);
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_tmdbErrorMessage(error));
    }
  }

  bool _isWorkGroup(CloudResourceMediaGroup group) {
    return _controller.works.any((work) => work.workKey == group.workKey);
  }

  Future<void> _editTitle(CloudResourceMediaGroup group) async {
    final entry = group.anchor;
    final workGroup = _isWorkGroup(group);
    final workRecord = workGroup ? _controller.workRecordForGroup(group) : null;
    final record = workGroup ? null : _controller.tmdbRecordFor(entry);
    var inputValue = workGroup
        ? workRecord?.scrapeTitleOverride ??
            workRecord?.metadata?.title ??
            group.seriesName
        : record?.effectiveTitle ?? entry.name;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        var saving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(workGroup ? '修改刮削名称' : '修改剧名'),
            content: TextFormField(
              key: const ValueKey<String>('cloud-title-input'),
              initialValue: inputValue,
              autofocus: true,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: workGroup ? 'TMDB 搜索名称' : '显示剧名',
                errorText: errorText,
                helperText:
                    workGroup ? '用于整部作品刮削，不会重命名网盘文件' : '只修改看影音中的显示，不会重命名网盘文件',
              ),
              onChanged: (value) => inputValue = value,
              onFieldSubmitted: saving
                  ? null
                  : (value) async {
                      await _saveEditedTitle(
                        group,
                        value,
                        dialogContext,
                        setDialogState,
                        (value) => errorText = value,
                        (value) => saving = value,
                      );
                    },
            ),
            actions: [
              if (workGroup
                  ? workRecord?.scrapeTitleOverride != null
                  : record?.customTitle != null)
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            if (workGroup) {
                              await _controller.clearScrapeTitle(group);
                            } else {
                              await _controller.clearCustomTitle(entry);
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                          } on Object {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                saving = false;
                                errorText = workGroup ? '修改刮削名称失败' : '修改剧名失败';
                              });
                            }
                          }
                        },
                  child: Text(
                    workGroup ? '清除刮削名称' : '恢复 TMDB 标题',
                  ),
                ),
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () => _saveEditedTitle(
                          group,
                          inputValue,
                          dialogContext,
                          setDialogState,
                          (value) => errorText = value,
                          (value) => saving = value,
                        ),
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveEditedTitle(
    CloudResourceMediaGroup group,
    String value,
    BuildContext dialogContext,
    StateSetter setDialogState,
    void Function(String? value) setError,
    void Function(bool value) setSaving,
  ) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      setDialogState(
        () => setError(
          _isWorkGroup(group) ? '刮削名称不能为空' : '剧名不能为空',
        ),
      );
      return;
    }
    setDialogState(() {
      setError(null);
      setSaving(true);
    });
    try {
      if (_isWorkGroup(group)) {
        await _controller.saveScrapeTitle(group, normalized);
      } else {
        await _controller.saveCustomTitle(group.anchor, normalized);
      }
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    } on Object {
      if (!dialogContext.mounted) return;
      setDialogState(() {
        setSaving(false);
        setError(
          _isWorkGroup(group) ? '修改刮削名称失败' : '修改剧名失败',
        );
      });
    }
  }

  Future<void> _editTags(CloudResourceMediaGroup group) async {
    final tags = await showDialog<List<String>>(
      context: context,
      builder: (_) => _CloudMediaTagEditorDialog(
        title: group.displayName,
        initialTags: _controller.customTagsForGroup(group),
      ),
    );
    if (!mounted || tags == null) return;
    try {
      await _controller.saveCustomTags(group, tags);
      if (mounted) _showMessage('标签已保存');
    } on Object {
      if (mounted) _showMessage('标签保存失败，请稍后重试');
    }
  }

  Future<void> _showMediaDetails(CloudResourceMediaGroup group) {
    return showCloudMediaDetailsDialog(
      context: context,
      item: _controller.detailsFor(group.anchor),
    );
  }

  Future<void> _scrapeSelectedSource() async {
    if (_batchScraping || _autoOrganizing) return;
    final workGroups = <String, CloudResourceMediaGroup>{
      for (final group in _controller.collection.groups)
        if (_isWorkGroup(group)) group.workKey: group,
    }.values.toList(growable: false);
    final entries = _controller.tmdbEntriesForSelectedSource;
    if (workGroups.isEmpty && entries.isEmpty) {
      _showMessage('当前来源没有需要刮削的资源');
      return;
    }
    setState(() {
      _batchScraping = true;
      _batchCurrent = 0;
      _batchTotal = workGroups.isNotEmpty ? workGroups.length : entries.length;
    });
    var matched = 0;
    var pending = 0;
    var noResult = 0;
    var failed = 0;
    try {
      if (workGroups.isNotEmpty) {
        for (final group in workGroups) {
          if (!mounted) return;
          setState(() => _batchCurrent++);
          try {
            final outcome = await _controller.scrapeWork(group);
            if (outcome.selected != null) {
              matched++;
            } else if (outcome.candidates.isNotEmpty) {
              pending++;
            } else {
              noResult++;
            }
          } on Object {
            failed++;
            continue;
          }
        }
      } else {
        for (final entry in entries) {
          if (!mounted) return;
          setState(() => _batchCurrent++);
          try {
            final outcome = await _controller.scrapeTmdb(entry);
            if (outcome.selected != null) {
              matched++;
            } else if (outcome.candidates.isNotEmpty) {
              pending++;
            } else {
              noResult++;
            }
          } on Object {
            failed++;
            continue;
          }
        }
      }
      if (mounted) {
        _showMessage(
          '当前来源刮削完成：成功 $matched 项，待确认 $pending 项，'
          '无结果 $noResult 项，失败 $failed 项',
        );
      }
    } finally {
      if (mounted) setState(() => _batchScraping = false);
    }
  }

  Future<void> _confirmAutoOrganize() async {
    final source = _controller.selectedSource;
    if (source == null || _autoOrganizing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自动批量整理'),
        content: Text(
          '将递归扫描“${source.name}”配置的媒体根目录，并使用 TMDB '
          '为高置信度作品更新中文显示名、海报和简介。\n\n'
          '存在歧义的资源会保持原名，之后仍可手动匹配。'
          '本操作只更新看影音中的元数据，不会修改网盘文件、目录或播放路径。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始整理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _autoOrganizeSource();
  }

  Future<void> _autoOrganizeSource() async {
    setState(() {
      _autoOrganizing = true;
      _autoOrganizeProgress = const CloudResourceAutoOrganizeProgress(
        phase: CloudResourceAutoOrganizePhase.scanning,
        scannedDirectories: 0,
        discoveredTargets: 0,
        completedTargets: 0,
        totalTargets: 0,
      );
    });
    try {
      final summary = await _controller.autoOrganizeSelectedSource(
        onProgress: (progress) {
          if (mounted) setState(() => _autoOrganizeProgress = progress);
        },
      );
      if (!mounted) return;
      _showMessage(
        '自动整理完成：成功 ${summary.matched} 项，待确认 ${summary.pending} 项，'
        '无结果 ${summary.noResult} 项，失败 ${summary.failed} 项，'
        '已跳过 ${summary.skipped} 项',
      );
    } on Object catch (error) {
      if (!mounted) return;
      final text = error.toString();
      if (text.contains('请先在设置中填写 TMDB API Key')) {
        _showMessage('请先在设置中填写 TMDB API Key');
      } else if (text.contains('正在刮削') || text.contains('正在进行')) {
        _showMessage('当前有刮削任务正在进行，请稍后再试');
      } else if (text.contains('目录深度') || text.contains('目录数量')) {
        _showMessage(text.replaceFirst('Bad state: ', ''));
      } else {
        _showMessage('自动整理失败，网盘浏览和播放不受影响');
      }
    } finally {
      if (mounted) {
        setState(() {
          _autoOrganizing = false;
          _autoOrganizeProgress = null;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static String _tmdbErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('请先在设置中填写 TMDB API Key')) {
      return '请先在设置中填写 TMDB API Key';
    }
    return 'TMDB 刮削失败，本地浏览和播放不受影响';
  }

  static String _manualEpisodeErrorMessage(Object error) {
    final text = error
        .toString()
        .replaceFirst(RegExp(r'^\w+(?:Error|Exception):\s*'), '')
        .trim();
    return text.isEmpty ? '剧集匹配失败，请重试' : text;
  }

  Future<void> _confirmRemoveSource() async {
    final source = _controller.selectedSource;
    if (source == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除网盘来源'),
        content: Text(
          '确定移除“${source.name}”吗？\n\n'
          '只会删除看影音中的来源、凭据、索引和缓存，'
          '不会删除网盘中的任何文件。',
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
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final callback = widget.onDeleteSource;
      if (callback != null) {
        await callback(source.id);
      } else {
        await Modular.get<CloudLibraryController>().delete(source.id);
      }
      await _controller.load();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网盘来源移除失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = _controller.sources;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _toolbar(sources),
            if (_controller.loading) const LinearProgressIndicator(),
            if (_controller.errorMessage != null)
              MaterialBanner(
                content: Text(_controller.errorMessage!),
                actions: [
                  TextButton(
                    onPressed: _controller.refresh,
                    child: const Text('重试'),
                  ),
                ],
              ),
            Expanded(
              child: _controller.selectedSource == null
                  ? sources.isEmpty && !_controller.loading
                      ? _emptyState()
                      : const Center(child: CircularProgressIndicator())
                  : _directoryContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(List<CloudSource> sources) {
    final selected = _controller.selectedSource;
    final toolbarState = _toolbarPolicy.evaluate(
      hasSelectedSource: selected != null,
      loading: _controller.loading,
      scanning: _controller.scanning,
      batchScraping: _batchScraping,
      autoOrganizing: _autoOrganizing,
      tmdbBusy: _controller.tmdbScrapingKeys.isNotEmpty,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          const Text(
            '网盘媒体库',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          if (sources.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey<String>('cloud-source-selector'),
                value: selected?.id,
                items: [
                  for (final source in sources)
                    DropdownMenuItem<String>(
                      value: source.id,
                      child: Text(source.name),
                    ),
                ],
                onChanged: !toolbarState.canChangeSource
                    ? null
                    : (sourceId) => _controller.selectSource(sourceId),
              ),
            ),
          if (sources.isNotEmpty) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              key: const ValueKey<String>('cloud-genre-filter'),
              tooltip: '筛选 TMDB 类型',
              enabled: selected != null,
              constraints: _cloudFilterMenuConstraints(context),
              onSelected: _handleCloudFilterSelection,
              itemBuilder: (_) => _cloudGenreMenuEntries(
                canScrape: toolbarState.canScrape,
              ),
              icon: _cloudFilterIcon(
                icon: Icons.movie_outlined,
                availableTags: _controller.availableGenres,
              ),
            ),
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              key: const ValueKey<String>('cloud-custom-tag-filter'),
              tooltip: '筛选自定义标签',
              enabled: selected != null,
              constraints: _cloudFilterMenuConstraints(context),
              onSelected: _handleCloudFilterSelection,
              itemBuilder: (_) => _cloudCustomTagMenuEntries(),
              icon: _cloudFilterIcon(
                icon: Icons.label_outline,
                availableTags: _controller.availableCustomTags,
              ),
            ),
          ],
          const Spacer(),
          PopupMenuButton<_CloudAddAction>(
            tooltip: '添加网盘',
            icon: const Icon(Icons.add_circle_outline),
            onSelected: (action) => unawaited(_addCloudSource(action)),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _CloudAddAction.quark,
                child: Text('添加夸克网盘'),
              ),
              PopupMenuItem(
                value: _CloudAddAction.baidu,
                child: Text('添加百度网盘'),
              ),
              PopupMenuItem(
                value: _CloudAddAction.xunlei,
                child: Text('添加迅雷网盘'),
              ),
              PopupMenuItem(
                value: _CloudAddAction.openList,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('添加 OpenList'),
                    SizedBox(width: 8),
                    Text('调试中'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: '管理网盘来源',
            onPressed: _manageSources,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '刷新当前来源',
            onPressed: toolbarState.canRefresh ? _controller.refresh : null,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<CloudToolbarAction>(
            tooltip: '更多网盘操作',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: _handleToolbarAction,
            itemBuilder: (context) => [
              _cloudToolbarMenuItem(
                context: context,
                action: CloudToolbarAction.manageHiddenVideos,
                icon: Icons.visibility_outlined,
                label: '管理已隐藏视频',
                enabled: toolbarState.canManageHiddenVideos,
              ),
              const PopupMenuDivider(),
              _cloudToolbarMenuItem(
                context: context,
                action: CloudToolbarAction.autoOrganize,
                icon: Icons.auto_awesome_motion,
                label: '自动整理当前来源',
                busy: _autoOrganizing,
                enabled: toolbarState.canAutoOrganize,
              ),
              _cloudToolbarMenuItem(
                context: context,
                action: CloudToolbarAction.scrape,
                icon: Icons.auto_awesome_outlined,
                label: '刮削当前来源',
                busy: _batchScraping,
                enabled: toolbarState.canScrape,
              ),
              const PopupMenuDivider(),
              _cloudToolbarMenuItem(
                context: context,
                action: CloudToolbarAction.removeSource,
                icon: Icons.delete_outline,
                label: '移除当前来源',
                enabled: toolbarState.canRemoveSource,
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  BoxConstraints _cloudFilterMenuConstraints(BuildContext context) {
    // 菜单高度控制在首屏首行海报附近，超出标签由菜单内部滚动展示。
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.56)
        .clamp(320.0, 480.0)
        .toDouble();
    return BoxConstraints(
      minWidth: 112,
      maxWidth: 280,
      maxHeight: maxHeight,
    );
  }

  List<PopupMenuEntry<String>> _cloudGenreMenuEntries({
    required bool canScrape,
  }) {
    final genres = _controller.availableGenres;
    final entries = <PopupMenuEntry<String>>[];
    if (genres.isEmpty) {
      entries.add(
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('暂无类型标签'),
        ),
      );
      entries.add(
        PopupMenuItem<String>(
          value: '__scrape_source__',
          enabled: canScrape,
          child: const Text('刮削当前来源生成标签'),
        ),
      );
    }
    if (_controller.selectedGenres.isNotEmpty) {
      entries.add(
        const PopupMenuItem<String>(
          value: '__clear__',
          child: Text('清除'),
        ),
      );
    }
    if (genres.isNotEmpty) {
      entries.add(
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('TMDB 类型'),
        ),
      );
      entries.addAll(genres.map(_checkedCloudTagItem));
    }
    return entries;
  }

  List<PopupMenuEntry<String>> _cloudCustomTagMenuEntries() {
    final customTags = _controller.availableCustomTags;
    final entries = <PopupMenuEntry<String>>[];
    if (customTags.isEmpty) {
      entries.add(
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('暂无自定义标签'),
        ),
      );
    } else {
      entries.add(
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('自定义标签'),
        ),
      );
      entries.addAll(customTags.map(_checkedCloudTagItem));
    }
    if (_controller.selectedGenres.isNotEmpty) {
      entries.insert(
        0,
        const PopupMenuItem<String>(
          value: '__clear__',
          child: Text('清除'),
        ),
      );
    }
    return entries;
  }

  void _handleCloudFilterSelection(String value) {
    if (value == '__clear__') {
      _controller.clearGenres();
    } else if (value == '__scrape_source__') {
      unawaited(_scrapeSelectedSource());
    } else {
      _controller.toggleGenre(value);
    }
  }

  Widget _cloudFilterIcon({
    required IconData icon,
    required Iterable<String> availableTags,
  }) {
    final available = availableTags.toSet();
    final selectedCount =
        _controller.selectedGenres.where(available.contains).length;
    if (selectedCount == 0) return Icon(icon);
    return Badge.count(
      count: selectedCount,
      child: Icon(icon),
    );
  }

  PopupMenuEntry<String> _checkedCloudTagItem(String value) {
    return CheckedPopupMenuItem<String>(
      value: value,
      checked: _controller.selectedGenres.contains(value),
      child: Text(value),
    );
  }

  PopupMenuItem<CloudToolbarAction> _cloudToolbarMenuItem({
    required BuildContext context,
    required CloudToolbarAction action,
    required IconData icon,
    required String label,
    required bool enabled,
    bool busy = false,
    bool destructive = false,
  }) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return PopupMenuItem<CloudToolbarAction>(
      value: action,
      enabled: enabled,
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
  }

  Future<void> _handleToolbarAction(CloudToolbarAction action) async {
    switch (action) {
      case CloudToolbarAction.manageHiddenVideos:
        await _manageHiddenVideos();
      case CloudToolbarAction.autoOrganize:
        await _confirmAutoOrganize();
      case CloudToolbarAction.scrape:
        await _scrapeSelectedSource();
      case CloudToolbarAction.removeSource:
        await _confirmRemoveSource();
    }
  }

  Future<void> _manageHiddenVideos() => showCloudHiddenVideoManagerDialog(
        context: context,
        records: _controller.hiddenVideos,
        onRestore: _controller.restoreHiddenVideo,
        onRestoreAll: _controller.restoreAllHiddenVideos,
      );

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 52),
            const SizedBox(height: 12),
            const Text('还没有可用的网盘来源'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => unawaited(
                    _addCloudSource(_CloudAddAction.quark),
                  ),
                  icon: const Icon(Icons.cloud_queue_outlined),
                  label: const Text('添加夸克网盘'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(
                    _addCloudSource(_CloudAddAction.baidu),
                  ),
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('添加百度网盘'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(
                    _addCloudSource(_CloudAddAction.xunlei),
                  ),
                  icon: const Icon(Icons.bolt_outlined),
                  label: const Text('添加迅雷网盘'),
                ),
                Tooltip(
                  message: 'OpenList（调试中）',
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(
                      _addCloudSource(_CloudAddAction.openList),
                    ),
                    icon: const Icon(Icons.cloud_outlined),
                    label: const Text('添加 OpenList'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _directoryContent() => Column(
        children: [
          if (_autoOrganizing && _autoOrganizeProgress != null)
            _autoOrganizeIndicator(_autoOrganizeProgress!)
          else if (_batchScraping)
            Padding(
              key: const ValueKey<String>('cloud-batch-scrape-progress'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('正在刮削 $_batchCurrent/$_batchTotal'),
                ],
              ),
            )
          else if (_controller.tmdbTotalCount > 0 &&
              _controller.tmdbCompletedCount < _controller.tmdbTotalCount)
            Padding(
              key: const ValueKey<String>('cloud-tmdb-progress'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: LinearProgressIndicator(
                value:
                    _controller.tmdbCompletedCount / _controller.tmdbTotalCount,
              ),
            ),
          if (_controller.scanning)
            Padding(
              key: const ValueKey<String>('cloud-scan-progress'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '正在后台扫描 ${_controller.scannedDirectories} 个目录',
                  ),
                ],
              ),
            ),
          Padding(
            key: const ValueKey<String>('cloud-resource-search-surface'),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索全部网盘资源',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: _controller.setQuery,
            ),
          ),
          Expanded(
            key: const ValueKey<String>('cloud-resource-poster-surface'),
            child: CloudResourcePosterWall(
              capabilities: widget.capabilities ?? detectAppPlatform(),
              sourceId: _controller.selectedSource!.id,
              sourceName: _controller.selectedSource!.name,
              collection: _controller.collection,
              scrapingKeys: _controller.tmdbScrapingKeys,
              searchQuery: _controller.query,
              hiddenVideoCount: _controller.hiddenVideos.length,
              subtitleVideoKeys: _subtitleVideoKeys(
                _controller.selectedSource!.id,
              ),
              onOpenGroup: _openGroup,
              onEditTitle: _editTitle,
              onEditTags: _editTags,
              onScrape: _scrapeEntry,
              onRematch: _rematchEntry,
              onManualMatch: _manualMatchEntry,
              onMatchEpisodes: _matchEpisodes,
              onDetails: _showMediaDetails,
              onHide: _hideVideos,
            ),
          ),
        ],
      );

  Widget _autoOrganizeIndicator(CloudResourceAutoOrganizeProgress progress) {
    return Padding(
      key: const ValueKey<String>('cloud-auto-organize-progress'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            progress.phase == CloudResourceAutoOrganizePhase.scanning
                ? '正在扫描目录 ${progress.scannedDirectories}，'
                    '已发现 ${progress.discoveredTargets} 项'
                : '正在整理 ${progress.completedTargets}/'
                    '${progress.totalTargets}',
          ),
        ],
      ),
    );
  }
}

class _CloudMediaTagEditorDialog extends StatefulWidget {
  const _CloudMediaTagEditorDialog({
    required this.title,
    required this.initialTags,
  });

  final String title;
  final List<String> initialTags;

  @override
  State<_CloudMediaTagEditorDialog> createState() =>
      _CloudMediaTagEditorDialogState();
}

class _CloudMediaTagEditorDialogState
    extends State<_CloudMediaTagEditorDialog> {
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

  void _addTag() {
    final value = _inputController.text.trim();
    if (value.isEmpty || value.length > CloudMediaTagRepository.maxTagLength) {
      return;
    }
    if (_tags.any((tag) => tag.toLowerCase() == value.toLowerCase())) {
      _inputController.clear();
      return;
    }
    if (_tags.length >= CloudMediaTagRepository.maxTagsPerResource) return;
    setState(() {
      _tags.add(value);
      _inputController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('管理标签 · ${widget.title}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('cloud-tag-input'),
                    controller: _inputController,
                    maxLength: CloudMediaTagRepository.maxTagLength,
                    decoration: const InputDecoration(
                      labelText: '新增标签',
                      hintText: '例如：收藏、待看',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('cloud-tag-add'),
                  tooltip: '添加标签',
                  onPressed: _addTag,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _tags
                    .map(
                      (tag) => InputChip(
                        label: Text(tag),
                        onDeleted: () => setState(() => _tags.remove(tag)),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey<String>('cloud-tag-save'),
          onPressed: () => Navigator.of(context).pop(List<String>.from(_tags)),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

enum _CloudAddAction { quark, baidu, xunlei, openList }
