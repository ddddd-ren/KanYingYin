import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
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
    required this.onOpenDirectory,
    required this.onPlay,
    required this.onScrape,
    required this.onRematch,
  });

  final String sourceId;
  final List<CloudFileEntry> entries;
  final Map<String, CloudResourceTmdbRecord> records;
  final Set<String> scrapingKeys;
  final CloudResourceEntryAction onOpenDirectory;
  final CloudResourceEntryAction onPlay;
  final CloudResourceEntryAction onScrape;
  final CloudResourceEntryAction onRematch;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('当前目录没有可播放视频或文件夹'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 180).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.72,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final key = cloudResourceTmdbKey(
              sourceId: sourceId,
              remoteId: entry.id,
              remotePath: entry.remotePath,
            );
            return _CloudResourceCard(
              entry: entry,
              record: records[key],
              scraping: scrapingKeys.contains(key),
              onTap: () =>
                  entry.isDirectory ? onOpenDirectory(entry) : onPlay(entry),
              onScrape: () => onScrape(entry),
              onRematch: () => onRematch(entry),
            );
          },
        );
      },
    );
  }
}

enum _ResourceAction { scrape, rematch }

class _CloudResourceCard extends StatelessWidget {
  const _CloudResourceCard({
    required this.entry,
    required this.record,
    required this.scraping,
    required this.onTap,
    required this.onScrape,
    required this.onRematch,
  });

  final CloudFileEntry entry;
  final CloudResourceTmdbRecord? record;
  final bool scraping;
  final VoidCallback onTap;
  final VoidCallback onScrape;
  final VoidCallback onRematch;

  @override
  Widget build(BuildContext context) {
    final metadata =
        record?.status == CloudResourceTmdbStatus.matched ? record : null;
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _poster(context, metadata),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: colors.surface.withValues(alpha: 0.86),
                      shape: const CircleBorder(),
                      child: PopupMenuButton<_ResourceAction>(
                        tooltip: '资源操作',
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (action) {
                          switch (action) {
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
                            value: _ResourceAction.scrape,
                            child: Text('TMDB 刮削'),
                          ),
                          PopupMenuItem(
                            value: _ResourceAction.rematch,
                            child: Text('重新匹配'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (scraping)
                    ColoredBox(
                      color: colors.scrim.withValues(alpha: 0.34),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metadata?.title ?? entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (metadata != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.outline),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (metadata?.rating != null)
                        Expanded(
                          child: Text(
                            '${metadata!.rating!.toStringAsFixed(1)} ★',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        )
                      else
                        Expanded(
                          child: Text(
                            entry.isDirectory
                                ? '文件夹'
                                : _formatBytes(entry.size),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colors.outline),
                          ),
                        ),
                      if (!entry.isDirectory && entry.modifiedAt != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(entry.modifiedAt!),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.outline),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _poster(
    BuildContext context,
    CloudResourceTmdbRecord? metadata,
  ) {
    final key = metadata == null
        ? null
        : ValueKey<String>('tmdb-poster-${metadata.stableKey}');
    final cached = metadata?.posterCachePath;
    if (cached != null && File(cached).existsSync()) {
      return Image.file(
        File(cached),
        key: key,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _posterFallback(context, key),
      );
    }
    final network = TmdbMatchSheet.imageUrl(metadata?.posterUrl, size: 'w500');
    if (network != null) {
      return Image.network(
        network,
        key: key,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _posterFallback(context, key),
      );
    }
    return _posterFallback(context, key);
  }

  Widget _posterFallback(BuildContext context, Key? key) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: key,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surfaceContainerHighest, colors.surfaceContainer],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        entry.isDirectory ? Icons.folder_outlined : Icons.movie_outlined,
        size: 46,
        color: entry.isDirectory ? colors.primary : colors.secondary,
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  static String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
