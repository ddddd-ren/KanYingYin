import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';

class LocalSeriesDetailPage extends StatelessWidget {
  const LocalSeriesDetailPage({
    super.key,
    required this.series,
    required this.onPlay,
  });

  final LocalMediaSeries series;
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
              child: Image.network(backdrop, fit: BoxFit.cover),
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
              subtitle: Text(episode.toFileItem().formattedSize),
              onTap: () => onPlay(episode),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
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
        child: Image.network(remote, fit: BoxFit.cover),
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
