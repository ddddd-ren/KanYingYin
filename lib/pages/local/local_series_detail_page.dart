import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/local_episode_scrape_flow.dart';
import 'package:kanyingyin/pages/local/manual_episode_match_flow.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';
import 'package:kanyingyin/widgets/tmdb_image_picker_dialog.dart';

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
    final backdrop = TmdbMatchSheet.imageUrl(
      metadata?.imageOverride.backdrop ?? metadata?.backdropUrl,
      size: 'w1280',
    );
    final poster = TmdbMatchSheet.imageUrl(
      metadata?.imageOverride.poster ?? metadata?.posterUrl,
      size: 'w500',
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(metadata?.title ?? series.displayTitle),
        actions: [
          if (metadata != null)
            PopupMenuButton<String>(
              tooltip: '更换刮削图',
              onSelected: (value) => _pickSeriesImage(context, value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'poster', child: Text('更换海报')),
                PopupMenuItem(value: 'backdrop', child: Text('更换背景图')),
                PopupMenuItem(value: 'clearPoster', child: Text('恢复海报默认')),
                PopupMenuItem(value: 'clearBackdrop', child: Text('恢复背景默认')),
              ],
            ),
        ],
      ),
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
                  PopupMenuItem(value: 'seasonImage', child: Text('更换本季海报')),
                  PopupMenuItem(value: 'episodeImage', child: Text('更换本集剧照')),
                  PopupMenuItem(
                      value: 'clearSeasonImage', child: Text('恢复本季海报默认')),
                  PopupMenuItem(
                      value: 'clearEpisodeImage', child: Text('恢复本集剧照默认')),
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
      releaseTags: [
        MediaReleaseTags(
          source: episode.source,
          codec: episode.codec,
          releaseGroup: episode.releaseGroup,
        ),
      ],
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
      case 'seasonImage':
        await _pickEpisodeImage(
          context,
          episode,
          kind: TmdbImageKind.poster,
        );
        return;
      case 'episodeImage':
        await _pickEpisodeImage(
          context,
          episode,
          kind: TmdbImageKind.still,
        );
        return;
      case 'clearSeasonImage':
        await controller.clearLocalTmdbImage(
          seriesName: _seriesName,
          kind: TmdbImageKind.poster,
          seasonNumber: episode.seasonNumber,
        );
        return;
      case 'clearEpisodeImage':
        await controller.clearLocalTmdbImage(
          seriesName: _seriesName,
          kind: TmdbImageKind.still,
          seasonNumber: episode.seasonNumber,
          episodeNumber: episode.episodeNumber,
        );
        return;
    }
  }

  Future<void> _pickSeriesImage(BuildContext context, String value) async {
    final metadata = _metadata;
    if (metadata == null) return;
    if (value == 'clearPoster' || value == 'clearBackdrop') {
      await controller.clearLocalTmdbImage(
        seriesName: _seriesName,
        kind: value == 'clearPoster'
            ? TmdbImageKind.poster
            : TmdbImageKind.backdrop,
      );
      return;
    }
    final kind =
        value == 'backdrop' ? TmdbImageKind.backdrop : TmdbImageKind.poster;
    final candidate = await TmdbImagePickerDialog.show(
      context: context,
      title: kind == TmdbImageKind.backdrop ? '更换背景图' : '更换海报',
      kind: kind,
      currentPath: kind == TmdbImageKind.backdrop
          ? metadata.imageOverride.backdrop
          : metadata.imageOverride.poster,
      images: () => controller.loadLocalTmdbImages(_seriesName, kind: kind),
    );
    if (candidate == null || !context.mounted) return;
    await controller.selectLocalTmdbImage(
      seriesName: _seriesName,
      kind: kind,
      filePath: candidate.filePath,
    );
  }

  Future<void> _pickEpisodeImage(
    BuildContext context,
    LocalMediaIndexItem episode, {
    required TmdbImageKind kind,
  }) async {
    final metadata = _metadata;
    final seasonNumber = episode.seasonNumber;
    if (metadata == null || seasonNumber == null) return;
    final episodeNumber =
        kind == TmdbImageKind.still ? episode.episodeNumber : null;
    final current = kind == TmdbImageKind.still
        ? metadata.imageOverride.episodeStills['$seasonNumber:$episodeNumber']
        : metadata.imageOverride.seasonPosters[seasonNumber];
    final candidate = await TmdbImagePickerDialog.show(
      context: context,
      title: kind == TmdbImageKind.still ? '更换本集剧照' : '更换本季海报',
      kind: kind,
      currentPath: current,
      images: () => controller.loadLocalTmdbImages(
        _seriesName,
        kind: kind,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      ),
    );
    if (candidate == null || !context.mounted) return;
    await controller.selectLocalTmdbImage(
      seriesName: _seriesName,
      kind: kind,
      filePath: candidate.filePath,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  TmdbMetadata? get _metadata {
    for (final episode in series.episodes) {
      if (episode.tmdb != null) return episode.tmdb;
    }
    return null;
  }

  String get _seriesName {
    final value = series.episodes
        .map((episode) => episode.seriesName.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    return value.isNotEmpty ? value : series.title;
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
