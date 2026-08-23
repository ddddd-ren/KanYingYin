import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/local_episode_scrape_flow.dart';
import 'package:kanyingyin/pages/local/manual_episode_match_flow.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

class LocalSeriesDetailPage extends StatelessWidget {
  const LocalSeriesDetailPage({
    super.key,
    required this.series,
    required this.controller,
    required this.onPlay,
  });

  final LocalMediaSeries series;
  final LocalController controller;
  final void Function(LocalMediaIndexItem episode) onPlay;

  @override
  Widget build(BuildContext context) {
    final metadata = _metadata;
    final backdrop =
        TmdbMatchSheet.imageUrl(metadata?.backdropUrl, size: 'w1280');
    final poster = TmdbMatchSheet.imageUrl(metadata?.posterUrl, size: 'w500');
    return Scaffold(
      appBar: AppBar(title: Text(metadata?.title ?? series.displayTitle)),
      body: ListView(
        children: [
          if (backdrop != null)
            AspectRatio(
              aspectRatio: 16 / 7,
              child: TmdbNetworkImage(url: backdrop, fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: _poster(poster),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(metadata?.title ?? series.displayTitle,
                          style: Theme.of(context).textTheme.headlineSmall),
                      if (metadata?.originalTitle != null) ...[
                        const SizedBox(height: 4),
                        Text(metadata!.originalTitle!,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                      const SizedBox(height: 10),
                      Text(_facts(metadata)),
                      if (metadata?.overview?.isNotEmpty == true) ...[
                        const SizedBox(height: 14),
                        Text(metadata!.overview!,
                            style: const TextStyle(height: 1.5)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text('剧集 (${series.episodeCount})',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final episode in series.episodes)
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(episode.displayTitle),
              subtitle: _episodeDetails(episode),
              trailing: PopupMenuButton<String>(
                tooltip: '单集操作',
                onSelected: (value) =>
                    _handleEpisodeAction(context, episode, value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'scrape', child: Text('重新识别此集')),
                  PopupMenuItem(value: 'match', child: Text('手动匹配此集')),
                  PopupMenuItem(
                    value: 'episode',
                    child: Text('匹配季度和集数'),
                  ),
                  PopupMenuItem(value: 'reassign', child: Text('更正作品归属')),
                ],
              ),
              onTap: () => onPlay(episode),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _episodeDetails(LocalMediaIndexItem episode) {
    final badges = const MediaTechnicalBadgeResolver().resolve(
      names: [episode.name, episode.path],
      resolution: episode.resolution,
      videoWidth: episode.videoWidth,
      videoHeight: episode.videoHeight,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badges.isNotEmpty) ...[
          const SizedBox(height: 5),
          MediaTechnicalBadgeRow(badges: badges),
          const SizedBox(height: 4),
        ],
        Text(episode.toFileItem().formattedSize),
      ],
    );
  }

  Future<void> _handleEpisodeAction(
    BuildContext context,
    LocalMediaIndexItem episode,
    String action,
  ) async {
    switch (action) {
      case 'scrape':
        await scrapeLocalEpisode(
          context: context,
          controller: controller,
          episode: episode,
        );
        return;
      case 'match':
        await openLocalEpisodeTmdbDialog(
          context: context,
          controller: controller,
          episode: episode,
        );
        return;
      case 'episode':
        await openLocalManualEpisodeMatch(
          context: context,
          controller: controller,
          originalName: episode.name,
          paths: <String>[episode.path],
        );
        return;
      case 'reassign':
        await openLocalManualEpisodeMatch(
          context: context,
          controller: controller,
          originalName: episode.name,
          paths: <String>[episode.path],
          reassignSeriesName: true,
        );
        return;
    }
  }

  TmdbMetadata? get _metadata {
    for (final episode in series.episodes) {
      if (episode.tmdb != null) return episode.tmdb;
    }
    return null;
  }

  Widget _poster(String? remote) {
    if (series.cover != null && File(series.cover!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(series.cover!), fit: BoxFit.cover),
      );
    }
    if (remote != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: TmdbNetworkImage(url: remote, fit: BoxFit.cover),
      );
    }
    return const ColoredBox(
      color: Colors.black12,
      child: Icon(Icons.movie_outlined, size: 42),
    );
  }

  String _facts(TmdbMetadata? metadata) {
    if (metadata == null) return '${series.episodeCount} 个视频';
    final values = <String>[
      metadata.mediaType == TmdbMediaType.movie ? '电影' : '剧集',
      if (metadata.releaseDate != null && metadata.releaseDate!.length >= 4)
        metadata.releaseDate!.substring(0, 4),
      if (metadata.rating != null) '评分 ${metadata.rating!.toStringAsFixed(1)}',
      '${series.episodeCount} 个视频',
    ];
    return values.join(' · ');
  }
}
