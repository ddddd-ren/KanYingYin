import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';

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
    this.preferLocalCover = false,
    this.heroTag,
    this.networkCoverProvider,
    this.localCoverProvider,
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
  final bool preferLocalCover;
  final Object? heroTag;
  final ImageProvider<Object>? networkCoverProvider;
  final ImageProvider<Object>? localCoverProvider;
}

class LibraryMediaGridViewData {
  LibraryMediaGridViewData({
    List<LibraryMediaItemViewData> items = const [],
    this.currentPath = '',
    this.isLoading = false,
    this.errorMessage,
    this.hasSearchFilter = false,
  }) : items = List<LibraryMediaItemViewData>.unmodifiable(items);

  final List<LibraryMediaItemViewData> items;
  final String currentPath;
  final bool isLoading;
  final String? errorMessage;
  final bool hasSearchFilter;
}

class LibraryMediaCoverFallback {
  const LibraryMediaCoverFallback._();

  static Widget build(
    LibraryMediaItemViewData item, {
    required WidgetBuilder placeholderBuilder,
  }) {
    Widget local(BuildContext context) => buildLocal(
          item,
          placeholderBuilder: placeholderBuilder,
        );
    Widget network(BuildContext context) => buildNetwork(
          item,
          localBuilder: placeholderBuilder,
        );
    if (item.preferLocalCover) {
      return buildLocal(item, placeholderBuilder: network);
    }
    return buildNetwork(item, localBuilder: local);
  }

  static Widget buildLocal(
    LibraryMediaItemViewData item, {
    required WidgetBuilder placeholderBuilder,
  }) {
    final provider = item.localCoverProvider;
    if (provider != null) {
      return Image(
        image: provider,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, _, __) => placeholderBuilder(context),
      );
    }
    final path = item.localCoverPath;
    if (path == null || path.isEmpty) {
      return Builder(builder: placeholderBuilder);
    }
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, _, __) => placeholderBuilder(context),
    );
  }

  static Widget buildNetwork(
    LibraryMediaItemViewData item, {
    required WidgetBuilder localBuilder,
  }) {
    final provider = item.networkCoverProvider;
    if (provider != null) {
      return Image(
        image: provider,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, _, __) => localBuilder(context),
      );
    }
    final url = item.networkCoverUrl;
    if (url == null || url.isEmpty) {
      return Builder(builder: localBuilder);
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, _, __) => localBuilder(context),
    );
  }
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
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: data.items.length,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = data.items.indexWhere((item) => item.id == key.value);
        return index < 0 ? null : index;
      },
      itemBuilder: (context, index) {
        final item = data.items[index];
        return _LibraryMediaTile(
          key: ValueKey<String>(item.id),
          item: item,
          onPlay: onPlay,
          onShowActions: onShowActions,
        );
      },
    );
  }
}

class _LibraryMediaTile extends StatefulWidget {
  const _LibraryMediaTile({
    super.key,
    required this.item,
    this.onPlay,
    this.onShowActions,
  });
  final LibraryMediaItemViewData item;
  final LibraryMediaAction? onPlay;
  final LibraryMediaAction? onShowActions;

  @override
  State<_LibraryMediaTile> createState() => _LibraryMediaTileState();
}

class _LibraryMediaTileState extends State<_LibraryMediaTile> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final item = widget.item;
    final details = <String>[
      item.infoText,
      if (item.mediaInfoText.isNotEmpty) item.mediaInfoText,
      item.modifiedText,
    ].where((part) => part.isNotEmpty).join('  ·  ');
    final cover = item.heroTag == null
        ? _cover(colors)
        : Hero(tag: item.heroTag!, child: _cover(colors));
    return ImmersiveMediaCard(
      cover: cover,
      title: item.title,
      subtitle: item.subtitle,
      details: details,
      overlayMode: ImmersiveMediaCardOverlayMode.hover,
      badges: <ImmersiveMediaCardBadge>[
        ImmersiveMediaCardBadge(
          icon: Icons.closed_caption_outlined,
          label: item.hasSubtitle ? '有字幕' : '无字幕',
        ),
        ImmersiveMediaCardBadge(
          icon: Icons.image_search_outlined,
          label: item.scrapeLabel,
          loading: item.isScraping,
        ),
      ],
      onLongPress: widget.onShowActions == null
          ? null
          : () async => await widget.onShowActions!(item),
      onSecondaryTap: widget.onShowActions == null
          ? null
          : () async => await widget.onShowActions!(item),
      onTap:
          widget.onPlay == null ? null : () async => await widget.onPlay!(item),
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
    return LibraryMediaCoverFallback.build(
      widget.item,
      placeholderBuilder: (_) => placeholder(),
    );
  }
}
