import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/features/library/application/media_card_info.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:path/path.dart' as p;

Future<void> showMediaLibraryDetailsDialog({
  required BuildContext context,
  required MediaLibrarySeries series,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => MediaLibraryDetailsDialog(series: series),
  );
}

class MediaLibraryDetailsDialog extends StatelessWidget {
  const MediaLibraryDetailsDialog({
    super.key,
    required this.series,
  });

  final MediaLibrarySeries series;

  @override
  Widget build(BuildContext context) {
    final resources = series.episodes;
    final totalSize = resources.fold<int>(
      0,
      (sum, episode) => sum + (episode.size ?? episode.localItem?.size ?? 0),
    );
    final seasons = resources
        .map((episode) => episode.seasonNumber)
        .whereType<int>()
        .where((season) => season > 0)
        .toSet()
        .toList(growable: false)
      ..sort();
    return GlassDialog(
      key: const ValueKey<String>('media-details-dialog'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '媒体详情',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _detail(context, '作品标题', series.title),
                      _detail(context, '来源', series.sourceName),
                      _detail(
                          context, '媒体类型', _mediaTypeLabel(series.mediaType)),
                      _detail(context, '资源数量', '${resources.length} 个视频'),
                      if (seasons.isNotEmpty)
                        _detail(
                          context,
                          '季度',
                          seasons.map((season) => '第 $season 季').join(' · '),
                        ),
                      if (totalSize > 0)
                        _detail(
                          context,
                          '总大小',
                          UnifiedMediaCardInfoBuilder.formatBytes(totalSize),
                        ),
                      if (series.tmdbRating != null)
                        _detail(
                          context,
                          'TMDB 评分',
                          series.tmdbRating!.toStringAsFixed(1),
                        ),
                      if (series.tmdbReleaseDate?.trim().isNotEmpty == true)
                        _detail(
                            context, '上映日期', series.tmdbReleaseDate!.trim()),
                      if (series.genres.isNotEmpty)
                        _detail(context, '类型标签', series.genres.join(' · ')),
                      if (series.tmdbOverview?.trim().isNotEmpty == true)
                        _detail(context, '简介', series.tmdbOverview!.trim()),
                      const Divider(height: 28),
                      Text(
                        '资源明细',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      for (var index = 0;
                          index < resources.length;
                          index++) ...[
                        _resource(context, resources[index]),
                        if (index != resources.length - 1)
                          const Divider(height: 24),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }

  Widget _resource(BuildContext context, MediaLibraryEpisode episode) {
    final local = episode.localItem;
    final path = local?.path ?? episode.remotePath ?? '';
    final size = episode.size ?? local?.size;
    final modifiedAt = episode.modifiedAt ?? local?.modified;
    final extension =
        p.extension(episode.name).replaceFirst('.', '').toUpperCase();
    final technicalBadges = const MediaTechnicalBadgeResolver().resolve(
      names: [
        episode.name,
        if (local != null) local.path,
        if (episode.remotePath != null) episode.remotePath!,
      ],
      resolution: local?.resolution,
      videoWidth: local?.videoWidth,
      videoHeight: local?.videoHeight,
    );
    final details = <String>[
      if (episode.seasonNumber != null || episode.episodeNumber != null)
        _seasonEpisode(episode),
      if (extension.isNotEmpty) extension,
      if (size != null && size > 0)
        UnifiedMediaCardInfoBuilder.formatBytes(size),
      if (modifiedAt != null)
        UnifiedMediaCardInfoBuilder.formatDate(modifiedAt),
      if (_hasSubtitle(episode)) '有字幕',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          episode.name,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (technicalBadges.isNotEmpty) ...[
          const SizedBox(height: 5),
          MediaTechnicalBadgeRow(badges: technicalBadges),
        ],
        if (details.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            details.join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (path.isNotEmpty) ...[
          const SizedBox(height: 6),
          SelectableText(path),
        ],
      ],
    );
  }

  String _mediaTypeLabel(TmdbMediaType? mediaType) => switch (mediaType) {
        TmdbMediaType.movie => '电影',
        TmdbMediaType.tv => '电视剧',
        null => '未知',
      };

  String _seasonEpisode(MediaLibraryEpisode episode) {
    final season = episode.seasonNumber;
    final number = episode.episodeNumber;
    if (season != null && number != null) {
      return 'S${season.toString().padLeft(2, '0')}'
          'E${number.toString().padLeft(2, '0')}';
    }
    if (season != null) return '第 $season 季';
    return '第 $number 集';
  }

  bool _hasSubtitle(MediaLibraryEpisode episode) =>
      episode.subtitleRemotePaths.isNotEmpty ||
      episode.subtitleRemoteRefs.isNotEmpty ||
      episode.localItem?.subtitlePath?.isNotEmpty == true;
}
