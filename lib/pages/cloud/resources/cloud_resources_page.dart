import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_episode_sheet.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_playback_request.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_poster_wall.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_media_details_dialog.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_tmdb_match_dialog.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/utils/logger.dart';

String cloudPlaybackFailureDiagnostic(CloudSource source, Object error) =>
    'CloudResourcesPage: playback failed '
    'provider=${source.type.name} sourceId=${source.id} '
    'stage=resolve-or-load errorType=${error.runtimeType}';

class CloudResourcesPage extends StatefulWidget {
  const CloudResourcesPage({
    super.key,
    this.controller,
    this.onAddOpenList,
    this.onAddQuark,
    this.onManageSources,
    this.onPlayRequest,
    this.onDeleteSource,
  });

  final CloudResourcesController? controller;
  final VoidCallback? onAddOpenList;
  final VoidCallback? onAddQuark;
  final VoidCallback? onManageSources;
  final FutureOr<void> Function(CloudResourcePlaybackRequest request)?
      onPlayRequest;
  final FutureOr<void> Function(String sourceId)? onDeleteSource;

  @override
  State<CloudResourcesPage> createState() => _CloudResourcesPageState();
}

class _CloudResourcesPageState extends State<CloudResourcesPage> {
  late final CloudResourcesController _controller;
  final CloudProviderRegistry _providerRegistry = CloudProviderRegistry();
  final CloudPlaybackResolver _playbackResolver = CloudPlaybackResolver();
  bool _batchScraping = false;
  int _batchCurrent = 0;
  int _batchTotal = 0;
  bool _autoOrganizing = false;
  CloudResourceAutoOrganizeProgress? _autoOrganizeProgress;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? Modular.get<CloudResourcesController>();
    _controller.addListener(_refresh);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _addOpenList() {
    final callback = widget.onAddOpenList;
    if (callback != null) {
      callback();
    } else {
      Modular.to.pushNamed('/settings/cloud-sources/openlist/edit');
    }
  }

  void _addQuark() {
    final callback = widget.onAddQuark;
    if (callback != null) {
      callback();
    } else {
      Modular.to.pushNamed('/settings/cloud-sources/quark/edit');
    }
  }

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
    try {
      await Modular.get<LocalVideoController>().openCloudPlayback(
        seriesTitle: request.seriesTitle,
        targets: request.targets,
        selectedStableId: request.selectedStableId,
        resolver: _playbackResolver.resolve,
      );
      if (mounted) Modular.to.pushNamed('/video/');
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        cloudPlaybackFailureDiagnostic(source, error),
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网盘视频解析或加载失败')),
      );
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
    );
    if (selected != null && mounted) await _play(group, selected);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          const Text(
            '网盘资源',
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
                onChanged: _controller.loading || _autoOrganizing
                    ? null
                    : (sourceId) => _controller.selectSource(sourceId),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: '自动整理当前来源',
            onPressed: selected == null ||
                    _controller.loading ||
                    _controller.scanning ||
                    _batchScraping ||
                    _autoOrganizing ||
                    _controller.tmdbScrapingKeys.isNotEmpty
                ? null
                : _confirmAutoOrganize,
            icon: const Icon(Icons.auto_awesome_motion),
          ),
          IconButton(
            tooltip: '刮削当前来源',
            onPressed: selected == null ||
                    _controller.loading ||
                    _controller.scanning ||
                    _batchScraping ||
                    _autoOrganizing
                ? null
                : _scrapeSelectedSource,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: '管理网盘来源',
            onPressed: _manageSources,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '移除当前来源',
            onPressed: selected == null ||
                    _controller.loading ||
                    _controller.scanning ||
                    _autoOrganizing
                ? null
                : _confirmRemoveSource,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: '刷新当前来源',
            onPressed: selected == null ||
                    _controller.loading ||
                    _controller.scanning ||
                    _autoOrganizing
                ? null
                : _controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

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
              children: [
                OutlinedButton.icon(
                  onPressed: _addOpenList,
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('添加 OpenList'),
                ),
                FilledButton.icon(
                  onPressed: _addQuark,
                  icon: const Icon(Icons.cloud_queue_outlined),
                  label: const Text('添加夸克网盘'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _directoryContent() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  _controller.selectedSource?.type == CloudSourceType.quark
                      ? Icons.cloud_queue_outlined
                      : Icons.cloud_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  _providerRegistry.providerName(
                    _controller.selectedSource!.type,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '已汇总全部媒体根目录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (_autoOrganizing && _autoOrganizeProgress != null)
            _autoOrganizeIndicator(_autoOrganizeProgress!)
          else if (_batchScraping)
            Padding(
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: LinearProgressIndicator(
                value:
                    _controller.tmdbCompletedCount / _controller.tmdbTotalCount,
              ),
            ),
          if (_controller.scanning)
            Padding(
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
            child: CloudResourcePosterWall(
              sourceId: _controller.selectedSource!.id,
              collection: _controller.collection,
              scrapingKeys: _controller.tmdbScrapingKeys,
              subtitleVideoKeys: _subtitleVideoKeys(
                _controller.selectedSource!.id,
              ),
              onOpenGroup: _openGroup,
              onEditTitle: _editTitle,
              onScrape: _scrapeEntry,
              onRematch: _rematchEntry,
              onManualMatch: _manualMatchEntry,
              onDetails: _showMediaDetails,
            ),
          ),
        ],
      );

  Widget _autoOrganizeIndicator(CloudResourceAutoOrganizeProgress progress) {
    return Padding(
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
