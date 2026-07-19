import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_episode_info.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
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
    final title = group.record?.effectiveTitle ?? group.seriesName;
    return SafeArea(
      child: SizedBox(
        key: const ValueKey<String>('cloud-resource-episode-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.72,
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
                        Text('${group.videos.length} 集'),
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
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: group.videos.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final video = group.videos[index];
                  final episode = LocalEpisodeParser().parse(
                    video.remotePath,
                  );
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
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
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
                },
              ),
            ),
          ],
        ),
      ),
    );
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
