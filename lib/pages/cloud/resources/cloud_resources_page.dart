import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_grid.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

class CloudResourcesPage extends StatefulWidget {
  const CloudResourcesPage({
    super.key,
    this.controller,
    this.onAddOpenList,
    this.onAddQuark,
    this.onManageSources,
    this.onPlay,
  });

  final CloudResourcesController? controller;
  final VoidCallback? onAddOpenList;
  final VoidCallback? onAddQuark;
  final VoidCallback? onManageSources;
  final CloudResourceEntryAction? onPlay;

  @override
  State<CloudResourcesPage> createState() => _CloudResourcesPageState();
}

class _CloudResourcesPageState extends State<CloudResourcesPage> {
  late final CloudResourcesController _controller;
  final CloudProviderRegistry _providerRegistry = CloudProviderRegistry();

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

  Future<void> _openDirectory(CloudFileEntry entry) =>
      _controller.openDirectory(
        CloudRemoteRef(id: entry.id, path: entry.remotePath),
      );

  Future<void> _play(CloudFileEntry entry) async {
    await widget.onPlay?.call(entry);
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
                onChanged: _controller.loading
                    ? null
                    : (sourceId) => _controller.selectSource(sourceId),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: '管理网盘来源',
            onPressed: _manageSources,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '返回上级',
            onPressed: _controller.canGoBack && !_controller.loading
                ? _controller.goBack
                : null,
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            tooltip: '刷新当前目录',
            onPressed: selected == null || _controller.loading
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
                    _controller.currentDirectory?.path ?? '媒体根目录',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索当前目录',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: _controller.setQuery,
            ),
          ),
          Expanded(
            child: CloudResourcesGrid(
              entries: _controller.visibleEntries,
              onOpenDirectory: _openDirectory,
              onPlay: _play,
            ),
          ),
        ],
      );
}
