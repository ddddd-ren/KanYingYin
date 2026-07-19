import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';

typedef CloudResourceEntryAction = FutureOr<void> Function(
  CloudFileEntry entry,
);

class CloudResourcesGrid extends StatelessWidget {
  const CloudResourcesGrid({
    super.key,
    required this.entries,
    required this.onOpenDirectory,
    required this.onPlay,
  });

  final List<CloudFileEntry> entries;
  final CloudResourceEntryAction onOpenDirectory;
  final CloudResourceEntryAction onPlay;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('当前目录没有可播放视频或文件夹'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 230).floor().clamp(2, 6);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.45,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _CloudResourceCard(
              entry: entry,
              onTap: () =>
                  entry.isDirectory ? onOpenDirectory(entry) : onPlay(entry),
            );
          },
        );
      },
    );
  }
}

class _CloudResourceCard extends StatelessWidget {
  const _CloudResourceCard({required this.entry, required this.onTap});

  final CloudFileEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                entry.isDirectory
                    ? Icons.folder_outlined
                    : Icons.movie_outlined,
                size: 34,
                color: entry.isDirectory ? colors.primary : colors.secondary,
              ),
              const Spacer(),
              Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              if (entry.isDirectory)
                Text(
                  '文件夹',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.outline),
                )
              else
                Row(
                  children: [
                    Text(
                      _formatBytes(entry.size),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.outline),
                    ),
                    if (entry.modifiedAt != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatDate(entry.modifiedAt!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.outline),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
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
