import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_episode_info.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';

Future<CloudFileEntry?> showCloudResourceEpisodeSheet({
  required BuildContext context,
  required String sourceId,
  required CloudResourceMediaGroup group,
  Set<String> subtitleVideoKeys = const <String>{},
}) {
  return showModalBottomSheet<CloudFileEntry>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _CloudResourceEpisodeSheet(
      sourceId: sourceId,
      group: group,
      subtitleVideoKeys: subtitleVideoKeys,
    ),
  );
}

class _CloudResourceEpisodeSheet extends StatelessWidget {
  const _CloudResourceEpisodeSheet({
    required this.sourceId,
    required this.group,
    required this.subtitleVideoKeys,
  });

  final String sourceId;
  final CloudResourceMediaGroup group;
  final Set<String> subtitleVideoKeys;

  @override
  Widget build(BuildContext context) {
    final title = group.displayName;
    return SafeArea(
      child: SizedBox(
        key: const ValueKey<String>('cloud-resource-episode-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          group.isWorkScoped
                              ? '${group.videos.length} 集'
                              : '${group.seasons.length} 季 · '
                                  '${group.videos.length} 集',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭选集',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: group.seasons.length,
                itemBuilder: (context, index) => _seasonSection(
                  context,
                  group.seasons[index],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seasonSection(
    BuildContext context,
    CloudResourceSeasonGroup season,
  ) {
    final seasonNumber = season.seasonNumber;
    final title = seasonNumber == null ? '未识别季度' : '第 $seasonNumber 季';
    final metadata = season.metadata;
    final year = _year(metadata?.airDate);
    final details = <String>[
      if (year != null) year,
      '${season.videos.length} 集',
    ].join(' · ');
    return Container(
      key: ValueKey<String>('cloud-season-${seasonNumber ?? 'unknown'}'),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  key: ValueKey<String>(
                    'cloud-season-poster-${seasonNumber ?? 'unknown'}',
                  ),
                  width: 92,
                  height: 138,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: _seasonPoster(context, season),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(details),
                      if (metadata?.overview?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 10),
                        Text(
                          metadata!.overview!.trim(),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (var index = 0; index < season.videos.length; index++) ...[
            _episodeTile(context, season.videos[index], index),
            if (index < season.videos.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _episodeTile(
    BuildContext context,
    CloudFileEntry video,
    int index,
  ) {
    final episode = LocalEpisodeParser().parse(video.remotePath);
    final label = _episodeLabel(episode, index);
    final hasSubtitle = subtitleVideoKeys.contains(
      cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: video.id,
        remotePath: video.remotePath,
      ),
    );
    return ListTile(
      leading: SizedBox(
        width: 68,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      title: Text(
        video.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_formatBytes(video.size)),
      trailing: hasSubtitle
          ? const Tooltip(
              message: '有字幕',
              child: Icon(Icons.closed_caption_outlined),
            )
          : null,
      onTap: () => Navigator.of(context).pop(video),
    );
  }

  Widget _seasonPoster(
    BuildContext context,
    CloudResourceSeasonGroup season,
  ) {
    final cached = season.metadata?.posterCachePath;
    if (cached != null && File(cached).existsSync()) {
      return Image.file(
        File(cached),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _seasonNetworkOrSeries(
          context,
          season,
        ),
      );
    }
    return _seasonNetworkOrSeries(context, season);
  }

  Widget _seasonNetworkOrSeries(
    BuildContext context,
    CloudResourceSeasonGroup season,
  ) {
    final url = TmdbMatchSheet.imageUrl(
      season.metadata?.posterUrl,
      size: 'w500',
    );
    if (url == null) return _seriesPoster(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _seriesPoster(context),
    );
  }

  Widget _seriesPoster(BuildContext context) {
    final cached =
        group.workRecord?.posterCachePath ?? group.record?.posterCachePath;
    if (cached != null && File(cached).existsSync()) {
      return Image.file(
        File(cached),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _seriesNetworkOrPlaceholder(context),
      );
    }
    return _seriesNetworkOrPlaceholder(context);
  }

  Widget _seriesNetworkOrPlaceholder(BuildContext context) {
    final url = TmdbMatchSheet.imageUrl(
      group.workRecord?.metadata?.posterUrl ?? group.record?.posterUrl,
      size: 'w500',
    );
    if (url == null) return _placeholder(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.secondaryContainer,
      child: Icon(
        Icons.tv_outlined,
        color: colors.onSecondaryContainer,
        size: 36,
      ),
    );
  }

  static String? _year(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.length < 4) return null;
    return int.tryParse(normalized.substring(0, 4)) == null
        ? null
        : normalized.substring(0, 4);
  }

  static String _episodeLabel(LocalEpisodeInfo? episode, int index) {
    if (episode == null) return '第 ${index + 1} 集';
    final season = episode.seasonNumber;
    final episodeNumber = episode.episodeNumber.toString().padLeft(2, '0');
    if (season == null) return 'E$episodeNumber';
    return 'S${season.toString().padLeft(2, '0')}E$episodeNumber';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}
