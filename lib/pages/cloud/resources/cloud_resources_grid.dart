import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_card_view_data.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';

typedef CloudResourceEntryAction = FutureOr<void> Function(
  CloudFileEntry entry,
);

class CloudResourcesGrid extends StatelessWidget {
  const CloudResourcesGrid({
    super.key,
    required this.sourceId,
    required this.entries,
    required this.records,
    required this.scrapingKeys,
    this.subtitleVideoKeys = const <String>{},
    required this.onOpenDirectory,
    required this.onPlay,
    required this.onEditTitle,
    required this.onScrape,
    required this.onRematch,
  });

  final String sourceId;
  final List<CloudFileEntry> entries;
  final Map<String, CloudResourceTmdbRecord> records;
  final Set<String> scrapingKeys;
  final Set<String> subtitleVideoKeys;
  final CloudResourceEntryAction onOpenDirectory;
  final CloudResourceEntryAction onPlay;
  final CloudResourceEntryAction onEditTitle;
  final CloudResourceEntryAction onScrape;
  final CloudResourceEntryAction onRematch;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('当前目录没有可播放视频或文件夹'));
    }
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
          itemCount: entries.length,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final index = entries.indexWhere(
              (entry) => _stableKey(entry) == key.value,
            );
            return index < 0 ? null : index;
          },
          itemBuilder: (context, index) {
            final entry = entries[index];
            final stableKey = _stableKey(entry);
            final record = records[stableKey];
            final data = CloudResourceCardViewData.fromEntry(
              entry: entry,
              record: record,
              scraping: scrapingKeys.contains(stableKey),
              hasSubtitle: subtitleVideoKeys.contains(stableKey),
            );
            return _CloudResourceCard(
              key: ValueKey<String>(stableKey),
              entry: entry,
              record: record,
              data: data,
              onTap: () =>
                  entry.isDirectory ? onOpenDirectory(entry) : onPlay(entry),
              onEditTitle: () => onEditTitle(entry),
              onScrape: () => onScrape(entry),
              onRematch: () => onRematch(entry),
            );
          },
        );
      },
    );
  }

  String _stableKey(CloudFileEntry entry) => cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: entry.id,
        remotePath: entry.remotePath,
      );
}

enum _ResourceAction { editTitle, scrape, rematch }

class _CloudResourceCard extends StatelessWidget {
  const _CloudResourceCard({
    super.key,
    required this.entry,
    required this.record,
    required this.data,
    required this.onTap,
    required this.onEditTitle,
    required this.onScrape,
    required this.onRematch,
  });

  final CloudFileEntry entry;
  final CloudResourceTmdbRecord? record;
  final CloudResourceCardViewData data;
  final VoidCallback onTap;
  final VoidCallback onEditTitle;
  final VoidCallback onScrape;
  final VoidCallback onRematch;

  @override
  Widget build(BuildContext context) {
    if (data.kind == CloudResourceCardKind.directory) {
      return _directoryCard(context);
    }
    return ImmersiveMediaCard(
      cover: _mediaPoster(context),
      title: data.title,
      subtitle: data.subtitle,
      details: data.details,
      badges: data.badges,
      loading: data.isScraping,
      overlayMode: ImmersiveMediaCardOverlayMode.always,
      trailing: _resourceMenu(context),
      onTap: onTap,
    );
  }

  Widget _directoryCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.primaryContainer.withValues(alpha: 0.72),
                    colors.surfaceContainer,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 58,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (data.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        data.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colors.outline),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (data.isScraping)
              IgnorePointer(
                child: ColoredBox(
                  color: colors.scrim.withValues(alpha: 0.34),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            Positioned(top: 4, right: 4, child: _resourceMenu(context)),
          ],
        ),
      ),
    );
  }

  Widget _resourceMenu(BuildContext context) {
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
              onEditTitle();
              return;
            case _ResourceAction.scrape:
              onScrape();
              return;
            case _ResourceAction.rematch:
              onRematch();
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

  Widget _mediaPoster(BuildContext context) {
    final key = record?.status == CloudResourceTmdbStatus.matched
        ? ValueKey<String>('tmdb-poster-${record!.stableKey}')
        : null;
    final poster = _cachedPoster(context) ?? _networkPoster(context);
    return key == null ? poster : KeyedSubtree(key: key, child: poster);
  }

  Widget? _cachedPoster(BuildContext context) {
    final path = data.posterCachePath;
    if (path == null || !File(path).existsSync()) return null;
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => _networkPoster(context),
    );
  }

  Widget _networkPoster(BuildContext context) {
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
          colors: [
            colors.secondaryContainer,
            colors.surfaceContainer,
          ],
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
}
