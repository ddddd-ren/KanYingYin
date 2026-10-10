import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/features/library/presentation/directory_address_dropdown.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/features/library/presentation/library_source_menu.dart';

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
    this.mediaCount = 0,
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
  final int mediaCount;
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
  final LibrarySourceMenu sourceMenu;
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
    final isAndroidTv = detectAppPlatform().isAndroidTv;
    return Column(
      children: [
        Padding(
          key: const ValueKey('library-path-command-surface'),
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
          child: LayoutBuilder(builder: (context, constraints) {
            final title = Row(children: [
              Icon(Icons.video_library_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Flexible(
                  child: Text('媒体库',
                      key: const ValueKey<String>('local-media-library-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600))),
              const SizedBox(width: 10),
              Text('${data.mediaCount} 部',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.outline)),
            ]);
            final address = DirectoryAddressDropdown(
              key: const ValueKey('library-path-breadcrumb-surface'),
              addressKey: const ValueKey<String>('library-path-address'),
              currentPath: data.currentPath,
              enabled: !data.isLoading,
              borderless: true,
              savedDirectories: [
                for (final source in sourceMenu.data.sources)
                  if (source.isAvailable)
                    DirectoryNavigationItem(
                        label: source.name,
                        path: source.path,
                        subtitle: source.path),
              ],
              recentDirectories: [
                for (final path in data.recentPaths)
                  DirectoryNavigationItem(
                      label: path.label, path: path.path, subtitle: path.path),
              ],
              loadChildren: onLoadChildDirectories ?? (_) async => const [],
              onChildSelected: (item) async {
                if (onChildDirectorySelected != null) {
                  await onChildDirectorySelected!(item);
                } else {
                  await (onOpenRecentPath ?? onBreadcrumbSelected)(item.path);
                }
              },
              onSubmitted: onPathSubmitted,
            );
            final actions = [
              _button(context, Icons.keyboard_arrow_up_rounded, '上级目录',
                  data.canNavigateUp ? onNavigateUp : null),
              _button(context, Icons.refresh, '刷新当前目录',
                  data.isLoading ? null : onRefresh),
              PopupMenuButton<LibraryMenuAction>(
                tooltip: '更多媒体库操作',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (action) async => await action(),
                itemBuilder: (context) => [
                  _menuAction('选择目录', data.isLoading ? null : onPickDirectory),
                  _menuAction(
                      '扫描所有媒体源', data.canScanLibrary ? onScanLibrary : null,
                      busy: data.isIndexing),
                  _menuAction(
                      '查看全部已索引作品', data.canOpenLibrary ? onOpenLibrary : null),
                  const PopupMenuDivider(),
                  _menuAction('读取当前目录媒体信息',
                      data.canReadMediaInfo ? onFetchMediaInfo : null,
                      busy: data.isFetchingMediaInfo),
                  _menuAction('生成当前目录缩略图',
                      data.canGenerateThumbnails ? onGenerateThumbnails : null,
                      busy: data.isFetchingThumbnails),
                  _menuAction('匹配媒体库影片信息',
                      data.canMatchMetadata ? onMatchMetadata : null,
                      busy: data.isMatchingMetadata),
                  if (sourceMenu.data.sources.isNotEmpty) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem<LibraryMenuAction>(
                        enabled: false, child: Text('媒体源管理')),
                    ...sourceMenu.managementEntries(context),
                  ],
                ],
              ),
            ];
            if (constraints.maxWidth < 600) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 4),
                    Row(children: [Expanded(child: address), ...actions]),
                  ]);
            }
            return Row(children: [
              Expanded(child: title),
              SizedBox(width: 250, child: address),
              const SizedBox(width: 8),
              ...actions,
            ]);
          }),
        ),
        if (data.status.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
                alignment: Alignment.centerLeft,
                child: _status(context, colors)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 1, 16, 7),
          child: Row(children: [
            Expanded(
                child: Container(
              key: const ValueKey('library-path-search-surface'),
              height: 38,
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: colors.outlineVariant, width: 0.75),
              ),
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: isAndroidTv ? _handleTvSearchKeyEvent : null,
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
            )),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: '排序',
              onSelected: (field) async => await onSort(field),
              itemBuilder: (_) => [
                for (final field in const {
                  'name': '名称',
                  'size': '大小',
                  'modified': '日期'
                }.entries)
                  CheckedPopupMenuItem(
                      value: field.key,
                      checked: data.sortBy == field.key,
                      child: Text(field.value)),
              ],
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('排序：${const {
                        'name': '名称',
                        'size': '大小',
                        'modified': '日期'
                      }[data.sortBy] ?? '名称'}'),
                  const SizedBox(width: 4),
                  Icon(
                      data.sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 14),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ]),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  PopupMenuItem<LibraryMenuAction> _menuAction(
          String label, LibraryMenuAction? action,
          {bool busy = false}) =>
      PopupMenuItem<LibraryMenuAction>(
        value: action,
        enabled: action != null,
        child: Row(children: [
          if (busy) ...[
            const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(label)),
        ]),
      );

  KeyEventResult _handleTvSearchKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction != null) {
      final moved =
          FocusManager.instance.primaryFocus?.focusInDirection(direction) ??
              false;
      return moved ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      FocusManager.instance.primaryFocus?.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _button(
    BuildContext context,
    IconData icon,
    String tooltip,
    FutureOr<void> Function()? callback,
  ) =>
      IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: callback == null ? null : () async => await callback(),
      );

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
