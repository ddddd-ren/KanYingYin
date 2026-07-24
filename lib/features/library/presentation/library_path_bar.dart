import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/presentation/directory_address_dropdown.dart';

typedef LibraryPathSubmit = Future<String?> Function(String path);

String normalizeLibraryPathAddress(String value) {
  return normalizeDirectoryAddress(value);
}

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
    this.currentPath = '',
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
  final String currentPath;
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
    required this.onPathSubmitted,
    this.onLoadChildDirectories,
    this.onChildDirectorySelected,
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
  final LibraryPathSubmit onPathSubmitted;
  final DirectoryChildrenLoader? onLoadChildDirectories;
  final DirectoryChildSelected? onChildDirectorySelected;
  final FutureOr<void> Function()? onFetchMediaInfo;
  final FutureOr<void> Function()? onGenerateThumbnails;
  final FutureOr<void> Function()? onMatchMetadata;
  final FutureOr<void> Function()? onCancelScan;
  final FutureOr<void> Function()? onShowFailures;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          key: const ValueKey('library-path-command-surface'),
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.outlineVariant, width: 0.75),
          ),
          child: Row(
            children: [
              _button(
                context,
                Icons.folder_open,
                '选择目录',
                data.isLoading ? null : onPickDirectory,
              ),
              const SizedBox(width: 4),
              sourceMenu,
              const SizedBox(width: 4),
              _busyButton(
                context,
                Icons.manage_search_outlined,
                '扫描媒体库',
                data.isIndexing,
                data.canScanLibrary ? onScanLibrary : null,
              ),
              const SizedBox(width: 4),
              _button(
                context,
                Icons.video_collection_outlined,
                '媒体库',
                data.canOpenLibrary ? onOpenLibrary : null,
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 22,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colors.outlineVariant,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: '最近目录',
                icon: const Icon(Icons.history, size: 20),
                style: _iconButtonStyle(colors),
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
                            Text(
                              path.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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
              _button(
                context,
                Icons.keyboard_arrow_up_rounded,
                '上级目录',
                data.canNavigateUp ? onNavigateUp : null,
              ),
              const SizedBox(width: 4),
              _button(
                context,
                Icons.refresh,
                '刷新',
                data.isLoading ? null : onRefresh,
              ),
              const SizedBox(width: 4),
              _busyButton(
                context,
                Icons.info_outline,
                '读取媒体信息',
                data.isFetchingMediaInfo,
                data.canReadMediaInfo ? onFetchMediaInfo : null,
              ),
              const SizedBox(width: 4),
              _busyButton(
                context,
                Icons.photo_camera_outlined,
                '生成缩略图',
                data.isFetchingThumbnails,
                data.canGenerateThumbnails ? onGenerateThumbnails : null,
              ),
              const SizedBox(width: 4),
              _busyButton(
                context,
                Icons.cloud_sync_outlined,
                '匹配影片信息',
                data.isMatchingMetadata,
                data.canMatchMetadata ? onMatchMetadata : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 145,
                      maxWidth: 250,
                    ),
                    child: DirectoryAddressDropdown(
                      key: const ValueKey('library-path-breadcrumb-surface'),
                      addressKey:
                          const ValueKey<String>('library-path-address'),
                      currentPath: data.currentPath,
                      enabled: !data.isLoading,
                      loadChildren:
                          onLoadChildDirectories ?? (_) async => const [],
                      onChildSelected: (item) async =>
                          await onChildDirectorySelected?.call(item),
                      onSubmitted: onPathSubmitted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              Expanded(child: _status(context, colors)),
              _sortChip(context, '名称', 'name'),
              const SizedBox(width: 4),
              _sortChip(context, '大小', 'size'),
              const SizedBox(width: 4),
              _sortChip(context, '日期', 'modified'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 1, 12, 7),
          child: Container(
            key: const ValueKey('library-path-search-surface'),
            height: 38,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: colors.outlineVariant, width: 0.75),
            ),
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
                        onPressed: onClearSearch,
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onChanged: onSearchChanged,
            ),
          ),
        ),
      ],
    );
  }

  ButtonStyle _iconButtonStyle(
    ColorScheme colors, {
    Color? backgroundColor,
  }) =>
      IconButton.styleFrom(
        padding: const EdgeInsets.all(4),
        minimumSize: const Size.square(32),
        maximumSize: const Size.square(32),
        backgroundColor: backgroundColor,
        hoverColor: colors.primary.withValues(alpha: 0.08),
        focusColor: colors.primary.withValues(alpha: 0.1),
        highlightColor: colors.primary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  Widget _button(
    BuildContext context,
    IconData icon,
    String tooltip,
    FutureOr<void> Function()? callback,
  ) =>
      IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        onPressed: callback == null ? null : () async => await callback(),
        style: _iconButtonStyle(Theme.of(context).colorScheme),
      );

  Widget _busyButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    bool busy,
    FutureOr<void> Function()? callback,
  ) =>
      IconButton(
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 20),
        tooltip: tooltip,
        onPressed: callback == null ? null : () async => await callback(),
        style: _iconButtonStyle(Theme.of(context).colorScheme),
      );

  Widget _sortChip(BuildContext context, String label, String field) {
    final active = data.sortBy == field;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async => await onSort(field),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: active ? colors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
              ),
              if (active) ...[
                const SizedBox(width: 2),
                Icon(
                  data.sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 12,
                  color: colors.onPrimaryContainer,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(BuildContext context, ColorScheme colors) {
    final status = data.status;
    final textTheme = Theme.of(context).textTheme;
    if (status.kind == LibraryDirectoryStatusKind.idle ||
        status.kind == LibraryDirectoryStatusKind.loading) {
      return Text(
        status.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(color: colors.outline),
      );
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
