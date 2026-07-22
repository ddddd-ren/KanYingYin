import 'dart:async';

import 'package:flutter/material.dart';

class LibraryBreadcrumbViewData {
  const LibraryBreadcrumbViewData({
    required this.label,
    required this.path,
    this.isCurrent = false,
  });
  final String label;
  final String path;
  final bool isCurrent;
}

class LibraryRecentPathViewData {
  const LibraryRecentPathViewData({required this.label, required this.path});
  final String label;
  final String path;
}

enum LibraryDirectoryStatusKind {
  idle,
  indexing,
  indexFailures,
  matchingMetadata,
  fetchingPosters,
  fetchingMediaInfo,
  fetchingThumbnails,
  loading,
}

class LibraryDirectoryStatusViewData {
  const LibraryDirectoryStatusViewData({
    required this.kind,
    required this.label,
    this.currentFile = '',
    this.progress,
    this.progressLabel = '',
  });
  final LibraryDirectoryStatusKind kind;
  final String label;
  final String currentFile;
  final double? progress;
  final String progressLabel;

  factory LibraryDirectoryStatusViewData.matchingMetadata({
    required String label,
    required int current,
    required int total,
  }) {
    return LibraryDirectoryStatusViewData(
      kind: LibraryDirectoryStatusKind.matchingMetadata,
      label: label,
      progressLabel: total > 0 ? '$current/$total' : '',
    );
  }
}

class LibraryPathBarViewData {
  LibraryPathBarViewData({
    required List<LibraryBreadcrumbViewData> breadcrumbs,
    required List<LibraryRecentPathViewData> recentPaths,
    required this.sortBy,
    required this.sortAscending,
    required this.status,
    this.searchKeyword = '',
    this.isLoading = false,
    this.isIndexing = false,
    this.isFetchingPosters = false,
    this.isFetchingMediaInfo = false,
    this.isFetchingThumbnails = false,
    this.isMatchingMetadata = false,
    this.canScanLibrary = false,
    this.canOpenLibrary = false,
    this.canNavigateUp = false,
    this.canReadMediaInfo = false,
    this.canGenerateThumbnails = false,
    this.canMatchMetadata = false,
  })  : breadcrumbs = List<LibraryBreadcrumbViewData>.unmodifiable(breadcrumbs),
        recentPaths = List<LibraryRecentPathViewData>.unmodifiable(recentPaths);
  final List<LibraryBreadcrumbViewData> breadcrumbs;
  final List<LibraryRecentPathViewData> recentPaths;
  final String sortBy;
  final bool sortAscending;
  final LibraryDirectoryStatusViewData status;
  final String searchKeyword;
  final bool isLoading;
  final bool isIndexing;
  final bool isFetchingPosters;
  final bool isFetchingMediaInfo;
  final bool isFetchingThumbnails;
  final bool isMatchingMetadata;
  final bool canScanLibrary;
  final bool canOpenLibrary;
  final bool canNavigateUp;
  final bool canReadMediaInfo;
  final bool canGenerateThumbnails;
  final bool canMatchMetadata;
}

class LibraryPathBar extends StatelessWidget {
  const LibraryPathBar({
    super.key,
    required this.data,
    required this.sourceMenu,
    required this.searchController,
    required this.onPickDirectory,
    required this.onRefresh,
    required this.onSort,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onBreadcrumbSelected,
    this.onScanLibrary,
    this.onOpenLibrary,
    this.onOpenRecentPath,
    this.onNavigateUp,
    this.onFetchPosters,
    this.onFetchMediaInfo,
    this.onGenerateThumbnails,
    this.onMatchMetadata,
    this.onCancelScan,
    this.onShowFailures,
  });

  final LibraryPathBarViewData data;
  final Widget sourceMenu;
  final TextEditingController searchController;
  final FutureOr<void> Function() onPickDirectory;
  final FutureOr<void> Function() onRefresh;
  final FutureOr<void> Function(String field) onSort;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final FutureOr<void> Function(String path) onBreadcrumbSelected;
  final FutureOr<void> Function()? onScanLibrary;
  final FutureOr<void> Function()? onOpenLibrary;
  final FutureOr<void> Function(String path)? onOpenRecentPath;
  final FutureOr<void> Function()? onNavigateUp;
  final FutureOr<void> Function()? onFetchPosters;
  final FutureOr<void> Function()? onFetchMediaInfo;
  final FutureOr<void> Function()? onGenerateThumbnails;
  final FutureOr<void> Function()? onMatchMetadata;
  final FutureOr<void> Function()? onCancelScan;
  final FutureOr<void> Function()? onShowFailures;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(
                bottom: BorderSide(color: colors.outlineVariant, width: 0.5))),
        child: Row(children: [
          _button(Icons.folder_open, '选择目录',
              data.isLoading ? null : onPickDirectory),
          const SizedBox(width: 4),
          sourceMenu,
          const SizedBox(width: 4),
          _busyButton(Icons.manage_search_outlined, '扫描媒体库', data.isIndexing,
              data.canScanLibrary ? onScanLibrary : null),
          const SizedBox(width: 4),
          _button(Icons.video_collection_outlined, '媒体库',
              data.canOpenLibrary ? onOpenLibrary : null),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: '最近目录',
            icon: const Icon(Icons.history, size: 20),
            enabled: !data.isLoading && data.recentPaths.isNotEmpty,
            onSelected: (path) async => await onOpenRecentPath?.call(path),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              for (final path in data.recentPaths)
                PopupMenuItem<String>(
                  value: path.path,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(path.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          path.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: colors.outline),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          _button(Icons.arrow_upward, '上级目录',
              data.canNavigateUp ? onNavigateUp : null),
          const SizedBox(width: 4),
          _button(Icons.refresh, '刷新', data.isLoading ? null : onRefresh),
          const SizedBox(width: 4),
          PopupMenuButton<_LibrarySecondaryAction>(
            tooltip: '更多媒体操作',
            icon: const Icon(Icons.more_horiz_rounded, size: 20),
            onSelected: _handleSecondaryAction,
            itemBuilder: (context) => [
              _secondaryMenuItem(
                action: _LibrarySecondaryAction.fetchPosters,
                icon: Icons.image_search_outlined,
                label: '获取海报',
                busy: data.isFetchingPosters,
                enabled: !data.isLoading &&
                    !data.isFetchingPosters &&
                    onFetchPosters != null,
              ),
              _secondaryMenuItem(
                action: _LibrarySecondaryAction.fetchMediaInfo,
                icon: Icons.info_outline,
                label: '读取媒体信息',
                busy: data.isFetchingMediaInfo,
                enabled: data.canReadMediaInfo && onFetchMediaInfo != null,
              ),
              _secondaryMenuItem(
                action: _LibrarySecondaryAction.generateThumbnails,
                icon: Icons.photo_camera_outlined,
                label: '生成缩略图',
                busy: data.isFetchingThumbnails,
                enabled:
                    data.canGenerateThumbnails && onGenerateThumbnails != null,
              ),
              _secondaryMenuItem(
                action: _LibrarySecondaryAction.matchMetadata,
                icon: Icons.cloud_sync_outlined,
                label: '批量刮削 TMDB 信息',
                busy: data.isMatchingMetadata,
                enabled: data.canMatchMetadata && onMatchMetadata != null,
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(child: _breadcrumbs(context, colors)),
        ]),
      ),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(child: _status(context, colors)),
            _sortChip(context, '名称', 'name'),
            const SizedBox(width: 4),
            _sortChip(context, '大小', 'size'),
            const SizedBox(width: 4),
            _sortChip(context, '日期', 'modified'),
          ])),
      Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: SizedBox(
              height: 38,
              child: TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                    hintText: '搜索当前目录',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: data.searchKeyword.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: onClearSearch),
                    filled: true,
                    fillColor:
                        colors.surfaceContainerHighest.withValues(alpha: 0.45),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8)),
                onChanged: onSearchChanged,
              ))),
    ]);
  }

  Widget _button(
          IconData icon, String tooltip, FutureOr<void> Function()? callback) =>
      IconButton(
          icon: Icon(icon, size: 20),
          tooltip: tooltip,
          onPressed: callback == null ? null : () async => await callback(),
          style: IconButton.styleFrom(
              padding: const EdgeInsets.all(4),
              minimumSize: const Size(32, 32)));

  Widget _busyButton(IconData icon, String tooltip, bool busy,
          FutureOr<void> Function()? callback) =>
      IconButton(
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 20),
          tooltip: tooltip,
          onPressed: callback == null ? null : () async => await callback(),
          style: IconButton.styleFrom(
              padding: const EdgeInsets.all(4),
              minimumSize: const Size(32, 32)));

  PopupMenuItem<_LibrarySecondaryAction> _secondaryMenuItem({
    required _LibrarySecondaryAction action,
    required IconData icon,
    required String label,
    required bool busy,
    required bool enabled,
  }) {
    return PopupMenuItem<_LibrarySecondaryAction>(
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
            Icon(icon, size: 18),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _handleSecondaryAction(
    _LibrarySecondaryAction action,
  ) async {
    switch (action) {
      case _LibrarySecondaryAction.fetchPosters:
        await onFetchPosters?.call();
      case _LibrarySecondaryAction.fetchMediaInfo:
        await onFetchMediaInfo?.call();
      case _LibrarySecondaryAction.generateThumbnails:
        await onGenerateThumbnails?.call();
      case _LibrarySecondaryAction.matchMetadata:
        await onMatchMetadata?.call();
    }
  }

  Widget _breadcrumbs(BuildContext context, ColorScheme colors) =>
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < data.breadcrumbs.length; i++) ...[
              if (i > 0)
                Icon(Icons.chevron_right, size: 16, color: colors.outline),
              GestureDetector(
                  onTap: data.breadcrumbs[i].isCurrent
                      ? null
                      : () async =>
                          await onBreadcrumbSelected(data.breadcrumbs[i].path),
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(data.breadcrumbs[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: data.breadcrumbs[i].isCurrent
                                      ? colors.onSurface
                                      : colors.primary,
                                  fontWeight: data.breadcrumbs[i].isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.normal)))),
            ],
          ]));

  Widget _sortChip(BuildContext context, String label, String field) {
    final active = data.sortBy == field;
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
        onTap: () async => await onSort(field),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: active ? colors.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          active ? colors.onPrimaryContainer : colors.outline)),
              if (active)
                Icon(
                    data.sortAscending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 12,
                    color: colors.onPrimaryContainer),
            ])));
  }

  Widget _status(BuildContext context, ColorScheme colors) {
    final status = data.status;
    final textTheme = Theme.of(context).textTheme;
    if (status.kind == LibraryDirectoryStatusKind.idle ||
        status.kind == LibraryDirectoryStatusKind.loading) {
      return Text(status.label,
          style: textTheme.bodySmall?.copyWith(color: colors.outline));
    }
    if (status.kind == LibraryDirectoryStatusKind.indexFailures) {
      return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(children: [
            Icon(Icons.error_outline, size: 16, color: colors.error),
            const SizedBox(width: 6),
            Expanded(
                child: Text(status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                        color: colors.error, fontWeight: FontWeight.w600))),
            TextButton(
                onPressed: onShowFailures == null
                    ? null
                    : () async => await onShowFailures!(),
                child: const Text('查看')),
          ]));
    }
    final showBar = status.kind == LibraryDirectoryStatusKind.indexing ||
        status.kind == LibraryDirectoryStatusKind.fetchingPosters;
    return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                if (!showBar) ...[
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8)
                ],
                Expanded(
                    child: Text(status.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600))),
                if (status.progressLabel.isNotEmpty)
                  Text(status.progressLabel,
                      style: textTheme.labelSmall
                          ?.copyWith(color: colors.primary)),
                if (status.kind == LibraryDirectoryStatusKind.indexing)
                  IconButton(
                      tooltip: '取消扫描',
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: onCancelScan == null
                          ? null
                          : () async => await onCancelScan!(),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 28, height: 28)),
              ]),
              if (showBar) ...[
                const SizedBox(height: 3),
                ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: status.progress, minHeight: 3)),
              ],
              if (status.currentFile.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(status.currentFile,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        textTheme.labelSmall?.copyWith(color: colors.outline)),
              ],
            ]));
  }
}

enum _LibrarySecondaryAction {
  fetchPosters,
  fetchMediaInfo,
  generateThumbnails,
  matchMetadata,
}
