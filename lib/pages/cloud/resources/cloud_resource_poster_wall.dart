import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_card_view_data.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';

typedef CloudResourceEntryAction = FutureOr<void> Function(
  CloudFileEntry entry,
);
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
    required this.onOpenDirectory,
    required this.onOpenGroup,
    required this.onEditTitle,
    required this.onScrape,
    required this.onRematch,
  });

  final String sourceId;
  final CloudResourceCollection collection;
  final Set<String> scrapingKeys;
  final Set<String> subtitleVideoKeys;
  final CloudResourceEntryAction onOpenDirectory;
  final CloudResourceGroupAction onOpenGroup;
  final CloudResourceEntryAction onEditTitle;
  final CloudResourceEntryAction onScrape;
  final CloudResourceEntryAction onRematch;

  @override
  Widget build(BuildContext context) {
    if (collection.folders.isEmpty && collection.groups.isEmpty) {
      return const Center(
        child: Text('当前目录没有符合识别条件的视频或文件夹'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (collection.folders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              key: const ValueKey<String>('cloud-folder-navigation'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final folder in collection.folders)
                  ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(folder.name),
                    tooltip: '打开 ${folder.name}',
                    onPressed: () => onOpenDirectory(folder),
                  ),
              ],
            ),
          ),
        if (collection.groups.isEmpty)
          const Expanded(
            child: Center(child: Text('当前目录没有符合识别条件的视频')),
          )
        else
          Expanded(child: _mediaGrid(context)),
      ],
    );
  }

  Widget _mediaGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 650
            ? 2
            : constraints.maxWidth < 1000
                ? 3
                : 4;
        double? extent;
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          final width =
              (constraints.maxWidth - 24 - 12 * (columns - 1)) / columns;
          extent = (width / 0.68).clamp(320.0, 680.0);
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.68,
            mainAxisExtent: extent,
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
            final scraping = group.videos.any(
              (video) => scrapingKeys.contains(_resourceKey(video)),
            );
            final hasSubtitle = group.videos.any(
              (video) => subtitleVideoKeys.contains(_resourceKey(video)),
            );
            final data = CloudResourceCardViewData.fromEntry(
              entry: anchor,
              record: group.record,
              scraping: scraping,
              hasSubtitle: hasSubtitle,
            );
            return ImmersiveMediaCard(
              key: ValueKey<String>(group.stableKey),
              cover: _mediaPoster(context, group.record, data),
              title: group.record?.effectiveTitle ?? group.seriesName,
              subtitle:
                  group.isSeries ? '${group.videos.length} 集' : anchor.name,
              details: data.details,
              badges: data.badges,
              loading: scraping,
              overlayMode: ImmersiveMediaCardOverlayMode.always,
              trailing: _resourceMenu(context, anchor),
              onTap: () => onOpenGroup(group),
            );
          },
        );
      },
    );
  }

  Widget _resourceMenu(BuildContext context, CloudFileEntry entry) {
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
              onEditTitle(entry);
              return;
            case _ResourceAction.scrape:
              onScrape(entry);
              return;
            case _ResourceAction.rematch:
              onRematch(entry);
              return;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _ResourceAction.editTitle,
            child: Text('修改剧名'),
          ),
          PopupMenuItem(
            value: _ResourceAction.scrape,
            child: Text('TMDB 刮削'),
          ),
          PopupMenuItem(
            value: _ResourceAction.rematch,
            child: Text('重新匹配'),
          ),
        ],
      ),
    );
  }

  Widget _mediaPoster(
    BuildContext context,
    CloudResourceTmdbRecord? record,
    CloudResourceCardViewData data,
  ) {
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

enum _ResourceAction { editTitle, scrape, rematch }
