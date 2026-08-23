import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_card_view_data.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/features/tv/presentation/tv_image_decode_policy.dart';
import 'package:kanyingyin/features/tv/presentation/tv_layout_policy.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';

typedef CloudResourceGroupAction = FutureOr<void> Function(
  CloudResourceMediaGroup group,
);

class CloudResourcePosterWall extends StatefulWidget {
  const CloudResourcePosterWall({
    super.key,
    required this.sourceId,
    this.sourceName = '',
    required this.collection,
    required this.scrapingKeys,
    this.searchQuery = '',
    this.subtitleVideoKeys = const <String>{},
    this.hiddenVideoCount = 0,
    required this.onOpenGroup,
    required this.onEditTitle,
    this.onEditTags,
    required this.onScrape,
    required this.onRematch,
    this.onManualMatch,
    this.onMatchEpisodes,
    this.onDetails,
    this.onHide,
    this.capabilities,
  });

  final String sourceId;
  final String sourceName;
  final CloudResourceCollection collection;
  final Set<String> scrapingKeys;
  final String searchQuery;
  final Set<String> subtitleVideoKeys;
  final int hiddenVideoCount;
  final CloudResourceGroupAction onOpenGroup;
  final CloudResourceGroupAction onEditTitle;
  final CloudResourceGroupAction? onEditTags;
  final CloudResourceGroupAction onScrape;
  final CloudResourceGroupAction onRematch;
  final CloudResourceGroupAction? onManualMatch;
  final CloudResourceGroupAction? onMatchEpisodes;
  final CloudResourceGroupAction? onDetails;
  final CloudResourceGroupAction? onHide;
  final AppPlatformCapabilities? capabilities;

  @override
  State<CloudResourcePosterWall> createState() =>
      _CloudResourcePosterWallState();
}

class _CloudResourcePosterWallState extends State<CloudResourcePosterWall> {
  String? _warmupIdentity;

  String get sourceId => widget.sourceId;
  String get sourceName => widget.sourceName;
  CloudResourceCollection get collection => widget.collection;
  Set<String> get scrapingKeys => widget.scrapingKeys;
  String get searchQuery => widget.searchQuery;
  Set<String> get subtitleVideoKeys => widget.subtitleVideoKeys;
  int get hiddenVideoCount => widget.hiddenVideoCount;
  CloudResourceGroupAction get onOpenGroup => widget.onOpenGroup;
  CloudResourceGroupAction get onEditTitle => widget.onEditTitle;
  CloudResourceGroupAction? get onEditTags => widget.onEditTags;
  CloudResourceGroupAction get onScrape => widget.onScrape;
  CloudResourceGroupAction get onRematch => widget.onRematch;
  CloudResourceGroupAction? get onManualMatch => widget.onManualMatch;
  CloudResourceGroupAction? get onMatchEpisodes => widget.onMatchEpisodes;
  CloudResourceGroupAction? get onDetails => widget.onDetails;
  CloudResourceGroupAction? get onHide => widget.onHide;
  AppPlatformCapabilities? get capabilities => widget.capabilities;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePosterWarmup();
  }

  @override
  void didUpdateWidget(covariant CloudResourcePosterWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePosterWarmup();
  }

  void _schedulePosterWarmup() {
    if (collection.groups.isEmpty) return;
    final platform = capabilities ?? detectAppPlatform();
    final decodeSize = TvImageDecodePolicy.poster(
      platform,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final limit = cloudPosterWarmupLimit(
      MediaQuery.sizeOf(context),
      maxCrossAxisExtent: 300,
      childAspectRatio: 0.68,
    );
    final paths = collection.groups
        .take(limit)
        .map(_cardData)
        .map((data) => data.posterCachePath)
        .toList(growable: false);
    final identity = paths.map((path) => path?.trim() ?? '').join('\u0000');
    if (_warmupIdentity == identity) return;
    _warmupIdentity = identity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _warmupIdentity != identity) return;
      unawaited(
        precacheCloudPosterFiles(
          context,
          paths,
          limit: limit,
          cacheWidth: decodeSize?.width,
          cacheHeight: decodeSize?.height,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (collection.groups.isEmpty) {
      final searching = searchQuery.trim().isNotEmpty;
      return Center(
        child: Text(
          searching
              ? '没有找到匹配的视频'
              : hiddenVideoCount > 0
                  ? '视频已隐藏，可从更多网盘操作中恢复'
                  : '该来源暂时没有符合识别条件的视频',
        ),
      );
    }
    return _mediaGrid(context);
  }

  Widget _mediaGrid(BuildContext context) {
    final platform = capabilities ?? detectAppPlatform();
    final policy = TvLayoutPolicy.forCapabilities(platform);
    final decodeSize = TvImageDecodePolicy.poster(
      platform,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return FocusTraversalGroup(
      key: const ValueKey<String>('cloud-resource-poster-focus-group'),
      child: GridView.builder(
        padding: policy.gridPadding(const EdgeInsets.all(12)),
        gridDelegate: policy.posterGridDelegate(
          fallbackMaxCrossAxisExtent: 300,
          fallbackChildAspectRatio: 0.68,
        ),
        itemCount: collection.groups.length,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final index = collection.groups.indexWhere(
            (group) => group.stableKey == key.value,
          );
          return index < 0 ? null : index;
        },
        itemBuilder: (context, index) {
          final group = collection.groups[index];
          final anchor = group.anchor;
          final data = _cardData(group);
          final range = data.unifiedSubtitle.contains(' · ')
              ? data.unifiedSubtitle.substring(
                  data.unifiedSubtitle.indexOf(' · ') + 3,
                )
              : '';
          final displaySubtitle = !group.isSeries && group.videos.length <= 1
              ? anchor.name
              : group.isSeries
                  ? '${group.uniqueEpisodeCount} 集'
                  : data.unifiedSubtitle.isNotEmpty
                      ? data.unifiedSubtitle
                      : group.videos.length > 1
                          ? '${group.videos.length} 个版本'
                          : anchor.name;
          final displayDetails = data.unifiedDetails.isNotEmpty
              ? [
                  if (range.isNotEmpty) range,
                  data.unifiedDetails,
                ].join(' · ')
              : data.details;
          return ImmersiveMediaCard(
            key: ValueKey<String>(group.stableKey),
            cover: _mediaPoster(context, group, data, decodeSize),
            title: group.isWorkScoped
                ? group.displayName
                : group.record?.effectiveTitle ?? group.seriesName,
            subtitle: displaySubtitle,
            details: displayDetails,
            badges: _badges(group, data),
            technicalBadges: data.technicalBadges,
            loading: data.isScraping,
            overlayMode: ImmersiveMediaCardOverlayMode.hover,
            trailing: _resourceMenu(context, group),
            onTap: () => onOpenGroup(group),
          );
        },
      ),
    );
  }

  CloudResourceCardViewData _cardData(CloudResourceMediaGroup group) {
    final scraping = group.isWorkScoped
        ? scrapingKeys.contains(group.workKey)
        : group.videos.any(
            (video) => scrapingKeys.contains(_resourceKey(video)),
          );
    final hasSubtitle = group.videos.any(
      (video) => subtitleVideoKeys.contains(_resourceKey(video)),
    );
    return group.isWorkScoped
        ? CloudResourceCardViewData.fromGroup(
            group: group,
            scraping: scraping,
            hasSubtitle: hasSubtitle,
            sourceName: sourceName,
          )
        : CloudResourceCardViewData.fromEntry(
            entry: group.anchor,
            record: group.record,
            scraping: scraping,
            hasSubtitle: hasSubtitle,
            sourceName: sourceName,
          );
  }

  Widget _resourceMenu(BuildContext context, CloudResourceMediaGroup group) {
    return Material(
      key: const ValueKey<String>('cloud-resource-action-surface'),
      type: MaterialType.transparency,
      shape: const CircleBorder(),
      child: PopupMenuButton<_ResourceAction>(
        tooltip: '资源操作',
        padding: EdgeInsets.zero,
        iconSize: 16,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(32),
          maximumSize: const Size.square(32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.more_vert),
        onSelected: (action) {
          switch (action) {
            case _ResourceAction.editTitle:
              onEditTitle(group);
              return;
            case _ResourceAction.editTags:
              onEditTags?.call(group);
              return;
            case _ResourceAction.scrape:
              onScrape(group);
              return;
            case _ResourceAction.rematch:
              onRematch(group);
              return;
            case _ResourceAction.manualMatch:
              onManualMatch?.call(group);
              return;
            case _ResourceAction.matchEpisodes:
              onMatchEpisodes?.call(group);
              return;
            case _ResourceAction.details:
              onDetails?.call(group);
              return;
            case _ResourceAction.hide:
              onHide?.call(group);
              return;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _ResourceAction.editTitle,
            child: Text(
              group.isWorkScoped ? '修改刮削名称' : '修改剧名',
            ),
          ),
          if (onEditTags != null)
            const PopupMenuItem(
              value: _ResourceAction.editTags,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sell_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('管理标签'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: _ResourceAction.scrape,
            child: Text('TMDB 刮削'),
          ),
          const PopupMenuItem(
            value: _ResourceAction.rematch,
            child: Text('重新匹配'),
          ),
          if (_needsManualConfirmation(group))
            const PopupMenuItem(
              value: _ResourceAction.manualMatch,
              child: Text('手动确认匹配'),
            ),
          if (onMatchEpisodes != null)
            const PopupMenuItem(
              value: _ResourceAction.matchEpisodes,
              child: Text('匹配剧集'),
            ),
          const PopupMenuItem(
            value: _ResourceAction.details,
            child: Text('媒体详情'),
          ),
          if (onHide != null) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _ResourceAction.hide,
              child: Text('隐藏视频'),
            ),
          ],
        ],
      ),
    );
  }

  List<ImmersiveMediaCardBadge> _badges(
    CloudResourceMediaGroup group,
    CloudResourceCardViewData data,
  ) {
    final source = <ImmersiveMediaCardBadge>[
      ...data.unifiedBadges,
      for (final badge in data.badges)
        if (!data.unifiedBadges.any((item) => item.label == badge.label)) badge,
    ];
    if (!_needsManualConfirmation(group) || onManualMatch == null) {
      return source;
    }
    return source
        .map(
          (badge) => badge.label == '需要确认'
              ? ImmersiveMediaCardBadge(
                  key: const ValueKey<String>('cloud-manual-match-badge'),
                  icon: badge.icon,
                  label: badge.label,
                  loading: badge.loading,
                  onTap: () => onManualMatch?.call(group),
                )
              : badge,
        )
        .toList(growable: false);
  }

  bool _needsManualConfirmation(CloudResourceMediaGroup group) =>
      group.workRecord?.status == CloudWorkTmdbStatus.conflict;

  Widget _mediaPoster(
    BuildContext context,
    CloudResourceMediaGroup group,
    CloudResourceCardViewData data,
    TvImageDecodeSize? decodeSize,
  ) {
    return CloudPosterImage(
      key: ValueKey<String>('cloud-poster-${group.stableKey}'),
      cachePath: data.posterCachePath,
      url: TmdbMatchSheet.imageUrl(data.posterUrl, size: 'w500'),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: decodeSize?.width,
      cacheHeight: decodeSize?.height,
      filterQuality: FilterQuality.medium,
      placeholderBuilder: _mediaPlaceholder,
    );
  }

  Widget _mediaPlaceholder(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const ValueKey<String>('cloud-media-placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.secondaryContainer, colors.surfaceContainer],
        ),
      ),
      child: Center(
        child: Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            color: colors.secondary.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.movie_outlined,
            size: 48,
            color: colors.secondary,
          ),
        ),
      ),
    );
  }

  String _resourceKey(CloudFileEntry entry) => cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: entry.id,
        remotePath: entry.remotePath,
      );
}

enum _ResourceAction {
  editTitle,
  editTags,
  scrape,
  rematch,
  manualMatch,
  matchEpisodes,
  details,
  hide,
}
