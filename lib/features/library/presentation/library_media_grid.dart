import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/features/tv/presentation/tv_image_decode_policy.dart';
import 'package:kanyingyin/features/tv/presentation/tv_layout_policy.dart';
import 'package:kanyingyin/bean/widget/skeleton_loader.dart';
import 'package:kanyingyin/bean/widget/empty_state.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

typedef LibraryMediaAction = FutureOr<void> Function(
  LibraryMediaItemViewData item,
);
typedef LibraryMediaTrailingBuilder = Widget Function(
  BuildContext context,
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
    this.unifiedSubtitle = '',
    this.unifiedDetails = '',
    this.unifiedBadges = const <ImmersiveMediaCardBadge>[],
    this.technicalBadges = const <MediaTechnicalBadge>[],
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
  final String unifiedSubtitle;
  final String unifiedDetails;
  final List<ImmersiveMediaCardBadge> unifiedBadges;
  final List<MediaTechnicalBadge> technicalBadges;
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
    TvImageDecodeSize? decodeSize,
    TmdbImageBytesLoader? bytesLoader,
  }) {
    Widget local(BuildContext context) => buildLocal(
          item,
          placeholderBuilder: placeholderBuilder,
          decodeSize: decodeSize,
        );
    Widget network(BuildContext context) => buildNetwork(
          item,
          localBuilder: placeholderBuilder,
          decodeSize: decodeSize,
          bytesLoader: bytesLoader,
        );
    if (item.preferLocalCover) {
      return buildLocal(
        item,
        placeholderBuilder: network,
        decodeSize: decodeSize,
      );
    }
    return buildNetwork(
      item,
      localBuilder: local,
      decodeSize: decodeSize,
      bytesLoader: bytesLoader,
    );
  }

  static Widget buildLocal(
    LibraryMediaItemViewData item, {
    required WidgetBuilder placeholderBuilder,
    TvImageDecodeSize? decodeSize,
  }) {
    final provider = item.localCoverProvider;
    if (provider != null) {
      return Image(
        image: ResizeImage.resizeIfNeeded(
          decodeSize?.width,
          decodeSize?.height,
          provider,
        ),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, __) => placeholderBuilder(context),
      );
    }
    final path = item.localCoverPath;
    if (path == null || path.isEmpty) {
      return Builder(builder: placeholderBuilder);
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: decodeSize?.width,
      cacheHeight: decodeSize?.height,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, _, __) => placeholderBuilder(context),
    );
  }

  static Widget buildNetwork(
    LibraryMediaItemViewData item, {
    required WidgetBuilder localBuilder,
    TvImageDecodeSize? decodeSize,
    TmdbImageBytesLoader? bytesLoader,
  }) {
    final provider = item.networkCoverProvider;
    if (provider != null) {
      return Image(
        image: ResizeImage.resizeIfNeeded(
          decodeSize?.width,
          decodeSize?.height,
          provider,
        ),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, __) => localBuilder(context),
      );
    }
    final url = item.networkCoverUrl;
    if (url == null || url.isEmpty) {
      return Builder(builder: localBuilder);
    }
    return TmdbNetworkImage(
      url: url,
      bytesLoader: bytesLoader,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: decodeSize?.width,
      cacheHeight: decodeSize?.height,
      filterQuality: FilterQuality.medium,
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
    this.trailingBuilder,
    this.capabilities,
    this.networkImageLoader,
  });

  final LibraryMediaGridViewData data;
  final ScrollController? scrollController;
  final LibraryMediaAction? onPlay;
  final LibraryMediaAction? onShowActions;
  final FutureOr<void> Function()? onPickDirectory;
  final FutureOr<void> Function()? onRetry;
  final VoidCallback? onClearSearch;
  final LibraryMediaTrailingBuilder? trailingBuilder;
  final AppPlatformCapabilities? capabilities;
  final TmdbImageBytesLoader? networkImageLoader;

  @override
  Widget build(BuildContext context) {
    final policy = TvLayoutPolicy.forCapabilities(
      capabilities ?? detectAppPlatform(),
    );
    if (data.isLoading && data.items.isEmpty) {
      return FocusTraversalGroup(
        key: const ValueKey<String>('library-media-grid-focus-group'),
        child: GridView.builder(
          padding: policy.gridPadding(const EdgeInsets.all(12)),
          gridDelegate: policy.posterGridDelegate(
            fallbackMaxCrossAxisExtent: 300,
            fallbackChildAspectRatio: 0.68,
          ),
          itemCount: policy.isAndroidTv ? 10 : 8, // 电视首屏保持两行五列占位
          itemBuilder: (context, index) => const MediaCardSkeleton(),
        ),
      );
    }
    if (data.errorMessage != null && data.items.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '加载失败',
        description: data.errorMessage!,
        actionLabel: '重试',
        actionIcon: Icons.refresh,
        action: onRetry == null ? null : () async => await onRetry!(),
      );
    }
    if (data.items.isEmpty) {
      if (data.hasSearchFilter) {
        return EmptyState(
          icon: Icons.search_off,
          title: '没有匹配的文件',
          description: '尝试使用其他关键词搜索',
          actionLabel: '清空搜索',
          actionIcon: Icons.clear,
          action: onClearSearch,
        );
      }
      if (data.currentPath.isEmpty) {
        return EmptyState(
          icon: Icons.folder_open,
          title: '请先设置本地文件目录',
          description: '设置 → 界面 → 本地文件默认路径',
          actionLabel: '选择文件夹',
          actionIcon: Icons.folder_outlined,
          action: onPickDirectory == null
              ? null
              : () async => await onPickDirectory!(),
        );
      }
      return EmptyState(
        icon: Icons.video_file_outlined,
        title: '没有可识别的视频',
        description: '仅显示大于 800MB 的视频文件',
        actionLabel: '切换文件夹',
        actionIcon: Icons.folder_outlined,
        action: onPickDirectory == null
            ? null
            : () async => await onPickDirectory!(),
      );
    }
    final decodeSize = TvImageDecodePolicy.poster(
      capabilities ?? detectAppPlatform(),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return FocusTraversalGroup(
      key: const ValueKey<String>('library-media-grid-focus-group'),
      child: GridView.builder(
        controller: scrollController,
        padding: policy.gridPadding(const EdgeInsets.all(12)),
        gridDelegate: policy.posterGridDelegate(
          fallbackMaxCrossAxisExtent: 300,
          fallbackChildAspectRatio: 0.68,
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
            decodeSize: decodeSize,
            onPlay: onPlay,
            onShowActions: onShowActions,
            trailingBuilder: trailingBuilder,
            networkImageLoader: networkImageLoader,
          );
        },
      ),
    );
  }
}

class _LibraryMediaTile extends StatefulWidget {
  const _LibraryMediaTile({
    super.key,
    required this.item,
    this.decodeSize,
    this.onPlay,
    this.onShowActions,
    this.trailingBuilder,
    this.networkImageLoader,
  });
  final LibraryMediaItemViewData item;
  final TvImageDecodeSize? decodeSize;
  final LibraryMediaAction? onPlay;
  final LibraryMediaAction? onShowActions;
  final LibraryMediaTrailingBuilder? trailingBuilder;
  final TmdbImageBytesLoader? networkImageLoader;

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
    final displaySubtitle =
        item.unifiedSubtitle.isNotEmpty ? item.unifiedSubtitle : item.subtitle;
    final displayDetails =
        item.unifiedDetails.isNotEmpty ? item.unifiedDetails : details;
    final badges = item.unifiedBadges.isNotEmpty
        ? item.unifiedBadges
        : <ImmersiveMediaCardBadge>[
            ImmersiveMediaCardBadge(
              icon: Icons.closed_caption_outlined,
              label: item.hasSubtitle ? '有字幕' : '无字幕',
            ),
            ImmersiveMediaCardBadge(
              icon: Icons.image_search_outlined,
              label: item.scrapeLabel,
              loading: item.isScraping,
            ),
          ];
    final cover = item.heroTag == null
        ? _cover(colors)
        : Hero(tag: item.heroTag!, child: _cover(colors));
    return ImmersiveMediaCard(
      cover: cover,
      title: item.title,
      subtitle: displaySubtitle,
      details: displayDetails,
      overlayMode: ImmersiveMediaCardOverlayMode.hover,
      trailing: widget.trailingBuilder?.call(context, item),
      badges: badges,
      technicalBadges: item.technicalBadges,
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
      decodeSize: widget.decodeSize,
      bytesLoader: widget.networkImageLoader,
    );
  }
}
