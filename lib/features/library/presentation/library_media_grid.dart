import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

typedef LibraryMediaAction = FutureOr<void> Function(
  LibraryMediaItemViewData item,
);

class LibraryMediaItemViewData {
  const LibraryMediaItemViewData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.infoText,
    required this.modifiedText,
    required this.hasMultipleEpisodes,
    required this.hasSubtitle,
    required this.scrapeLabel,
    this.mediaInfoText = '',
    this.localCoverPath,
    this.networkCoverUrl,
    this.isScraping = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String infoText;
  final String mediaInfoText;
  final String modifiedText;
  final bool hasMultipleEpisodes;
  final bool hasSubtitle;
  final String scrapeLabel;
  final String? localCoverPath;
  final String? networkCoverUrl;
  final bool isScraping;
}

class LibraryMediaGridViewData {
  const LibraryMediaGridViewData({
    this.items = const [],
    this.currentPath = '',
    this.isLoading = false,
    this.errorMessage,
    this.hasSearchFilter = false,
  });

  final List<LibraryMediaItemViewData> items;
  final String currentPath;
  final bool isLoading;
  final String? errorMessage;
  final bool hasSearchFilter;
}

class LibraryMediaGrid extends StatelessWidget {
  const LibraryMediaGrid({
    super.key,
    required this.data,
    this.scrollController,
    this.onPlay,
    this.onShowActions,
    this.onPickDirectory,
    this.onRetry,
    this.onClearSearch,
  });

  final LibraryMediaGridViewData data;
  final ScrollController? scrollController;
  final LibraryMediaAction? onPlay;
  final LibraryMediaAction? onShowActions;
  final FutureOr<void> Function()? onPickDirectory;
  final FutureOr<void> Function()? onRetry;
  final VoidCallback? onClearSearch;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (data.isLoading && data.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (data.errorMessage != null && data.items.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colors.error),
                  const SizedBox(height: 12),
                  Text(data.errorMessage!,
                      textAlign: TextAlign.center,
                      style:
                          textTheme.bodyMedium?.copyWith(color: colors.error)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                      onPressed:
                          onRetry == null ? null : () async => await onRetry!(),
                      child: const Text('重试')),
                ],
              )));
    }
    if (data.items.isEmpty) {
      if (data.hasSearchFilter) {
        return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off, size: 48, color: colors.outline),
          const SizedBox(height: 12),
          Text('没有匹配的文件',
              style: textTheme.bodyLarge?.copyWith(color: colors.outline)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: onClearSearch,
              icon: const Icon(Icons.close),
              label: const Text('清空搜索')),
        ]));
      }
      if (data.currentPath.isEmpty) {
        return Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open, size: 48, color: colors.outline),
                    const SizedBox(height: 12),
                    Text('请先设置本地文件目录',
                        style: textTheme.bodyLarge
                            ?.copyWith(color: colors.outline)),
                    const SizedBox(height: 8),
                    Text('设置 → 界面 → 本地文件默认路径',
                        style: textTheme.bodySmall
                            ?.copyWith(color: colors.outline)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                        onPressed: onPickDirectory == null
                            ? null
                            : () async => await onPickDirectory!(),
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择文件夹')),
                  ],
                )));
      }
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.video_file_outlined, size: 48, color: colors.outline),
        const SizedBox(height: 12),
        Text('没有可识别的视频',
            style: textTheme.bodyLarge?.copyWith(color: colors.outline)),
        const SizedBox(height: 8),
        Text('仅显示大于 800MB 的视频文件',
            style: textTheme.bodySmall?.copyWith(color: colors.outline)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
            onPressed: onPickDirectory == null
                ? null
                : () async => await onPickDirectory!(),
            icon: const Icon(Icons.folder_open),
            label: const Text('切换文件夹')),
      ]));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final mediaSize = MediaQuery.sizeOf(context);
      final isTablet = !_isDesktop &&
          mediaSize.shortestSide >= 600 &&
          mediaSize.shortestSide / mediaSize.longestSide >= 9 / 16;
      final count = _isDesktop
          ? (constraints.maxWidth < 900 ? 3 : 4)
          : isTablet
              ? 4
              : 3;
      final spacing = _isDesktop ? 12.0 : 8.0;
      final padding = _isDesktop ? 12.0 : 8.0;
      double? extent;
      if (_isDesktop &&
          constraints.maxWidth.isFinite &&
          constraints.maxWidth > 0) {
        final width =
            (constraints.maxWidth - padding * 2 - spacing * (count - 1)) /
                count;
        extent = (width / 0.68).clamp(320.0, 680.0);
      }
      return GridView.builder(
        controller: scrollController,
        padding: EdgeInsets.all(padding),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: 0.68,
          mainAxisExtent: extent,
        ),
        itemCount: data.items.length,
        itemBuilder: (context, index) => _LibraryMediaTile(
          item: data.items[index],
          onPlay: onPlay,
          onShowActions: onShowActions,
        ),
      );
    });
  }
}

class _LibraryMediaTile extends StatefulWidget {
  const _LibraryMediaTile(
      {required this.item, this.onPlay, this.onShowActions});
  final LibraryMediaItemViewData item;
  final LibraryMediaAction? onPlay;
  final LibraryMediaAction? onShowActions;

  @override
  State<_LibraryMediaTile> createState() => _LibraryMediaTileState();
}

class _LibraryMediaTileState extends State<_LibraryMediaTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onLongPress: widget.onShowActions == null
              ? null
              : () async => await widget.onShowActions!(widget.item),
          onSecondaryTap: widget.onShowActions == null
              ? null
              : () async => await widget.onShowActions!(widget.item),
          onTap: widget.onPlay == null
              ? null
              : () async => await widget.onPlay!(widget.item),
          child: Stack(fit: StackFit.expand, children: [
            _cover(colors),
            IgnorePointer(
                child: AnimatedOpacity(
              opacity: _hovered ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: _overlay(context),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _cover(ColorScheme colors) {
    Widget placeholder() => DecoratedBox(
          decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.82)),
          child: Center(
              child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.16),
                      shape: BoxShape.circle),
                  child: Icon(
                      widget.item.hasMultipleEpisodes
                          ? Icons.video_collection_outlined
                          : Icons.play_circle_fill,
                      size: 48,
                      color: colors.primary))),
        );
    Widget local() {
      final path = widget.item.localCoverPath;
      if (path == null || path.isEmpty) return placeholder();
      return Image.file(File(path),
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => placeholder());
    }

    final url = widget.item.networkCoverUrl;
    if (url == null || url.isEmpty) return local();
    return Image.network(url,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => local());
  }

  Widget _overlay(BuildContext context) {
    final item = widget.item;
    final textTheme = Theme.of(context).textTheme;
    final details = [
      item.infoText,
      if (item.mediaInfoText.isNotEmpty) item.mediaInfoText,
      item.modifiedText
    ].where((part) => part.isNotEmpty).join('  ·  ');
    return DecoratedBox(
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.2),
            Colors.black.withValues(alpha: 0.82)
          ],
              stops: const [
            0,
            0.42,
            1
          ])),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.15)),
              const SizedBox(height: 6),
              Text(item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                      height: 1.25)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _chip(context, Icons.closed_caption_outlined,
                    item.hasSubtitle ? '有字幕' : '无字幕'),
                _chip(context, Icons.image_search_outlined, item.scrapeLabel,
                    loading: item.isScraping),
              ]),
            ],
          )),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label,
      {bool loading = false}) {
    return DecoratedBox(
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (loading)
              const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.8, color: Colors.white))
            else
              Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w500)),
          ])),
    );
  }
}
