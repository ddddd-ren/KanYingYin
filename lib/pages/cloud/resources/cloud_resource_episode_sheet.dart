import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/features/tv/presentation/tv_episode_tile_surface.dart';
import 'package:kanyingyin/features/tv/presentation/tv_image_decode_policy.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/local/tmdb_match_sheet.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';

Future<CloudFileEntry?> showCloudResourceEpisodeSheet({
  required BuildContext context,
  required String sourceId,
  required CloudResourceMediaGroup group,
  Set<String> subtitleVideoKeys = const <String>{},
  AppPlatformCapabilities? capabilities,
}) {
  return showModalBottomSheet<CloudFileEntry>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _CloudResourceEpisodeSheet(
      sourceId: sourceId,
      group: group,
      subtitleVideoKeys: subtitleVideoKeys,
      capabilities: capabilities,
    ),
  );
}

class _CloudResourceEpisodeSheet extends StatelessWidget {
  const _CloudResourceEpisodeSheet({
    required this.sourceId,
    required this.group,
    required this.subtitleVideoKeys,
    required this.capabilities,
  });

  final String sourceId;
  final CloudResourceMediaGroup group;
  final Set<String> subtitleVideoKeys;
  final AppPlatformCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    final title = group.displayName;
    final platform = capabilities ?? detectAppPlatform();
    final decodeSize = TvImageDecodePolicy.seasonThumbnail(
      platform,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final isTv = platform.isAndroidTv;
    final visibleSeasons = group.seasons.isEmpty && group.videos.isNotEmpty
        ? <CloudResourceSeasonGroup>[
            CloudResourceSeasonGroup(
              seasonNumber: null,
              videos: group.videos,
            ),
          ]
        : group.seasons;
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
                          !group.isSeries
                              ? '${group.videos.length} 个版本'
                              : group.isWorkScoped
                                  ? '${group.uniqueEpisodeCount} 集'
                                  : '${group.seasons.length} 季 · '
                                      '${group.uniqueEpisodeCount} 集',
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
              child: isTv
                  ? FocusTraversalGroup(
                      policy: WidgetOrderTraversalPolicy(),
                      child: _episodeList(
                        visibleSeasons,
                        decodeSize: decodeSize,
                        isTv: true,
                      ),
                    )
                  : _episodeList(
                      visibleSeasons,
                      decodeSize: decodeSize,
                      isTv: false,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _episodeList(
    List<CloudResourceSeasonGroup> visibleSeasons, {
    required TvImageDecodeSize? decodeSize,
    required bool isTv,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: visibleSeasons.length,
      itemBuilder: (context, index) => _seasonSection(
        context,
        visibleSeasons[index],
        decodeSize,
        isTv: isTv,
        autofocusFirstEpisode: index == 0,
      ),
    );
  }

  Widget _seasonSection(
    BuildContext context,
    CloudResourceSeasonGroup season,
    TvImageDecodeSize? decodeSize, {
    required bool isTv,
    required bool autofocusFirstEpisode,
  }) {
    final seasonNumber = season.seasonNumber;
    final title = !group.isSeries
        ? '可选版本'
        : seasonNumber == null
            ? '未识别季度'
            : '第 $seasonNumber 季';
    final metadata = season.metadata;
    final year = _year(metadata?.airDate);
    final details = <String>[
      if (year != null) year,
      group.isSeries
          ? '${season.uniqueEpisodeCount} 集'
          : '${season.videos.length} 个版本',
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
                    child: _seasonPoster(context, season, decodeSize),
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
            _episodeTile(
              context,
              season.videos[index],
              index,
              isTv: isTv,
              autofocus: autofocusFirstEpisode && index == 0,
            ),
            if (index < season.videos.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _episodeTile(
    BuildContext context,
    CloudFileEntry video,
    int index, {
    required bool isTv,
    required bool autofocus,
  }) {
    final hasIndexedEpisode = video.episodeNumber != null;
    final parsed =
        hasIndexedEpisode ? null : LocalEpisodeParser().parse(video.remotePath);
    final episodeLabel = _episodeLabel(
      isSeries: group.isSeries,
      seasonNumber: hasIndexedEpisode
          ? video.seasonNumber
          : video.seasonNumber ?? parsed?.seasonNumber,
      episodeNumber: video.episodeNumber ?? parsed?.episodeNumber,
      index: index,
    );
    final variant = video.variantLabel ?? _variantLabel(video.name);
    final label = variant == null ? episodeLabel : '$episodeLabel · $variant';
    final hasSubtitle = subtitleVideoKeys.contains(
      cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: video.id,
        remotePath: video.remotePath,
      ),
    );
    final technicalBadges = const MediaTechnicalBadgeResolver().resolve(
      names: [video.name, video.remotePath],
    );
    final tile = ListTile(
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (technicalBadges.isNotEmpty) ...[
            const SizedBox(height: 5),
            MediaTechnicalBadgeRow(badges: technicalBadges),
            const SizedBox(height: 4),
          ],
          Text(_formatBytes(video.size)),
        ],
      ),
      trailing: hasSubtitle
          ? const Tooltip(
              message: '有字幕',
              child: Icon(Icons.closed_caption_outlined),
            )
          : null,
      onTap: isTv ? null : () => Navigator.of(context).pop(video),
    );
    if (!isTv) return tile;
    return TvEpisodeTileSurface(
      autofocus: autofocus,
      onPressed: () => Navigator.of(context).pop(video),
      child: tile,
    );
  }

  Widget _seasonPoster(
    BuildContext context,
    CloudResourceSeasonGroup season,
    TvImageDecodeSize? decodeSize,
  ) {
    return CloudPosterImage(
      cachePath: season.metadata?.posterCachePath ??
          group.workRecord?.posterCachePath ??
          group.record?.posterCachePath,
      url: TmdbMatchSheet.imageUrl(
        season.metadata?.posterUrl ??
            group.workRecord?.metadata?.posterUrl ??
            group.record?.posterUrl,
        size: 'w500',
      ),
      fit: BoxFit.cover,
      cacheWidth: decodeSize?.width,
      cacheHeight: decodeSize?.height,
      filterQuality: FilterQuality.medium,
      placeholderBuilder: _placeholder,
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

  static String _episodeLabel({
    required bool isSeries,
    required int? seasonNumber,
    required int? episodeNumber,
    required int index,
  }) {
    if (!isSeries) return '版本 ${index + 1}';
    if (episodeNumber == null) return '第 ${index + 1} 集';
    final episodeToken = episodeNumber.toString().padLeft(2, '0');
    if (seasonNumber == null) return 'E$episodeToken';
    return 'S${seasonNumber.toString().padLeft(2, '0')}E$episodeToken';
  }

  static String? _variantLabel(String name) {
    final matches = RegExp(r'\[([^\[\]]+)\](?=\.[^.]+$|$)').allMatches(name);
    if (matches.isEmpty) return null;
    final value = matches.last.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
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
