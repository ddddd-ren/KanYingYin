import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_card_view_data.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';

typedef CloudResourceGroupAction = FutureOr<void> Function(
  CloudResourceMediaGroup group,
);

class CloudResourcePosterWall extends StatelessWidget {
  const CloudResourcePosterWall({
    super.key,
    required this.sourceId,
    required this.collection,
    required this.scrapingKeys,
    this.subtitleVideoKeys = const <String>{},
    required this.onOpenGroup,
    required this.onEditTitle,
    required this.onScrape,
    required this.onRematch,
    this.onManualMatch,
    this.onDetails,
  });

  final String sourceId;
  final CloudResourceCollection collection;
  final Set<String> scrapingKeys;
  final Set<String> subtitleVideoKeys;
  final CloudResourceGroupAction onOpenGroup;
  final CloudResourceGroupAction onEditTitle;
  final CloudResourceGroupAction onScrape;
  final CloudResourceGroupAction onRematch;
  final CloudResourceGroupAction? onManualMatch;
  final CloudResourceGroupAction? onDetails;

  @override
  Widget build(BuildContext context) {
    if (collection.groups.isEmpty) {
      return const Center(
        child: Text('该来源暂时没有符合识别条件的视频'),
      );
    }
    return _mediaGrid(context);
  }

  Widget _mediaGrid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.68,
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
        final scraping = group.isWorkScoped
            ? scrapingKeys.contains(group.workKey)
            : group.videos.any(
                (video) => scrapingKeys.contains(_resourceKey(video)),
              );
        final hasSubtitle = group.videos.any(
          (video) => subtitleVideoKeys.contains(_resourceKey(video)),
        );
        final data = group.isWorkScoped
            ? CloudResourceCardViewData.fromGroup(
                group: group,
                scraping: scraping,
              )
            : CloudResourceCardViewData.fromEntry(
                entry: anchor,
                record: group.record,
                scraping: scraping,
                hasSubtitle: hasSubtitle,
              );
        return ImmersiveMediaCard(
          key: ValueKey<String>(group.stableKey),
          cover: _mediaPoster(context, group, data),
          title: group.isWorkScoped
              ? group.displayName
              : group.record?.effectiveTitle ?? group.seriesName,
          subtitle:
              group.isSeries ? '${group.uniqueEpisodeCount} 集' : anchor.name,
          details: data.details,
          badges: _badges(group, data),
          loading: scraping,
          overlayMode: ImmersiveMediaCardOverlayMode.hover,
          trailing: _resourceMenu(context, group),
          onTap: () => onOpenGroup(group),
        );
      },
    );
  }

  Widget _resourceMenu(BuildContext context, CloudResourceMediaGroup group) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: 0.86),
      shape: const CircleBorder(),
      child: PopupMenuButton<_ResourceAction>(
        tooltip: '资源操作',
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (action) {
          switch (action) {
            case _ResourceAction.editTitle:
              onEditTitle(group);
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
            case _ResourceAction.details:
              onDetails?.call(group);
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
          const PopupMenuItem(
            value: _ResourceAction.details,
            child: Text('媒体详情'),
          ),
        ],
      ),
    );
  }

  List<ImmersiveMediaCardBadge> _badges(
    CloudResourceMediaGroup group,
    CloudResourceCardViewData data,
  ) {
    if (!_needsManualConfirmation(group) || onManualMatch == null) {
      return data.badges;
    }
    return data.badges
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
  ) {
    final record = group.record;
    if (group.isWorkScoped && group.seasonNumber != null) {
      return KeyedSubtree(
        key: ValueKey<String>('season-poster-${group.seasonNumber}'),
        child: _cachedPoster(context, data) ?? _networkPoster(context, data),
      );
    }
    final key = record?.status == CloudResourceTmdbStatus.matched
        ? ValueKey<String>('tmdb-poster-${record!.stableKey}')
        : null;
    final poster =
        _cachedPoster(context, data) ?? _networkPoster(context, data);
    return key == null ? poster : KeyedSubtree(key: key, child: poster);
  }

  Widget? _cachedPoster(
    BuildContext context,
    CloudResourceCardViewData data,
  ) {
    final path = data.posterCachePath;
    if (path == null || !File(path).existsSync()) return null;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => _networkPoster(context, data),
    );
  }

  Widget _networkPoster(
    BuildContext context,
    CloudResourceCardViewData data,
  ) {
    final url = TmdbMatchSheet.imageUrl(data.posterUrl, size: 'w500');
    if (url == null) return _mediaPlaceholder(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => _mediaPlaceholder(context),
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

enum _ResourceAction { editTitle, scrape, rematch, manualMatch, details }
