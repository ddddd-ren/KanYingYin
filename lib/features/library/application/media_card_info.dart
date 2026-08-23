import 'package:flutter/material.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:path/path.dart' as p;

/// 所有媒体库海报浮层共用的展示数据。
class UnifiedMediaCardInfo {
  UnifiedMediaCardInfo({
    required this.title,
    required this.subtitle,
    required this.details,
    required List<ImmersiveMediaCardBadge> badges,
    required List<MediaTechnicalBadge> technicalBadges,
  })  : badges = List<ImmersiveMediaCardBadge>.unmodifiable(badges),
        technicalBadges =
            List<MediaTechnicalBadge>.unmodifiable(technicalBadges);

  final String title;
  final String subtitle;
  final String details;
  final List<ImmersiveMediaCardBadge> badges;
  final List<MediaTechnicalBadge> technicalBadges;
}

/// 统一生成本地、网盘和分类入口使用的海报信息。
class UnifiedMediaCardInfoBuilder {
  const UnifiedMediaCardInfoBuilder._();

  static UnifiedMediaCardInfo forSeries(
    MediaLibrarySeries series, {
    String? categoryLabel,
  }) {
    final episodes = series.episodes;
    final seasonNumbers = episodes
        .map((episode) => episode.seasonNumber)
        .whereType<int>()
        .where((season) => season > 0)
        .toSet()
        .toList()
      ..sort();
    final title = _titleWithSeason(series.title, seasonNumbers);
    final mediaTypeLabel = _mediaTypeLabel(series.mediaType);
    final subtitle = _episodeSubtitle(
      episodes,
      isMovie: series.mediaType == TmdbMediaType.movie,
    );
    final details = _details(
      episodes: episodes,
      rating: series.tmdbRating,
      mediaTypeLabel: mediaTypeLabel,
      releaseDate: series.tmdbReleaseDate,
    );
    final badges = <ImmersiveMediaCardBadge>[];
    const resolver = MediaTechnicalBadgeResolver();
    final technicalBadges = resolver.aggregate([
      for (final episode in episodes)
        resolver.resolve(
          names: [
            episode.name,
            if (episode.localItem != null) episode.localItem!.path,
            if (episode.remotePath != null) episode.remotePath!,
          ],
          releaseTags: [episode.releaseTags],
          resolution: episode.localItem?.resolution,
          videoWidth: episode.localItem?.videoWidth,
          videoHeight: episode.localItem?.videoHeight,
        ),
    ]);
    final sourceLabel = series.isAvailable ? series.sourceName : '来源不可用';
    if (sourceLabel.trim().isNotEmpty) {
      badges.add(
        ImmersiveMediaCardBadge(
          icon: series.sourceKind == MediaSourceKind.local
              ? Icons.storage_outlined
              : Icons.cloud_outlined,
          label: sourceLabel,
        ),
      );
    }
    final normalizedCategory = categoryLabel?.trim() ?? '';
    final normalizedType = mediaTypeLabel?.trim() ?? '';
    if (normalizedCategory.isNotEmpty) {
      badges.add(
        ImmersiveMediaCardBadge(
          icon: _categoryIcon(normalizedCategory),
          label: normalizedCategory,
        ),
      );
    } else if (normalizedType.isNotEmpty) {
      badges.add(
        ImmersiveMediaCardBadge(
          icon: Icons.category_outlined,
          label: normalizedType,
        ),
      );
    }
    if (episodes.any(_episodeHasSubtitle)) {
      badges.add(
        const ImmersiveMediaCardBadge(
          icon: Icons.closed_caption_outlined,
          label: '有字幕',
        ),
      );
    }
    badges.add(
      ImmersiveMediaCardBadge(
        icon: Icons.image_search_outlined,
        label: _isScraped(series) ? '已刮削' : '未刮削',
      ),
    );
    return UnifiedMediaCardInfo(
      title: title,
      subtitle: subtitle,
      details: details,
      badges: badges,
      technicalBadges: technicalBadges,
    );
  }

  /// 本地目录页没有统一媒体索引对象时也使用相同的排版规则。
  static UnifiedMediaCardInfo forLocalGroup(
    String title, {
    required Iterable<String> names,
    required Iterable<int> sizes,
    required Iterable<DateTime> modifiedAt,
    required Iterable<int?> episodeNumbers,
    required Iterable<int?> seasonNumbers,
    required bool hasSubtitle,
    required String scrapeLabel,
    String? mediaTypeLabel,
  }) {
    final seasonValues = seasonNumbers.toList(growable: false);
    final episodeValues = episodeNumbers.toList(growable: false);
    final episodes = <MediaLibraryEpisode>[
      for (var index = 0; index < names.length; index++)
        MediaLibraryEpisode.cloud(
          stableId: 'local-card-$index',
          name: names.elementAt(index),
          sourceId: 'local',
          sourceName: '本地',
          isAvailable: true,
          remoteId: 'local-card-$index',
          remotePath: '/local-card-$index',
          size: sizes.elementAt(index),
          modifiedAt: modifiedAt.elementAt(index),
          seasonNumber: seasonValues.elementAtOrNull(index),
          episodeNumber: episodeValues.elementAtOrNull(index),
          subtitleRemotePaths: hasSubtitle ? const ['/subtitle.srt'] : const [],
        ),
    ];
    final info = forSeries(
      MediaLibrarySeries(
        key: 'local-card',
        seriesKey: title,
        title: title,
        sourceKind: MediaSourceKind.local,
        sourceId: 'local',
        sourceName: '本地',
        isAvailable: true,
        episodes: episodes,
        mediaType:
            mediaTypeLabel == '电影' ? TmdbMediaType.movie : TmdbMediaType.tv,
      ),
    );
    final badges = info.badges
        .map(
          (badge) => badge.label == '已刮削'
              ? ImmersiveMediaCardBadge(
                  icon: badge.icon,
                  label: scrapeLabel,
                  loading: scrapeLabel == '正在刮削',
                )
              : badge,
        )
        .toList(growable: false);
    return UnifiedMediaCardInfo(
      title: info.title,
      subtitle: info.subtitle,
      details: info.details,
      badges: badges,
      technicalBadges: info.technicalBadges,
    );
  }

  static String _titleWithSeason(String title, List<int> seasons) {
    final value = title.trim();
    if (value.isEmpty || seasons.length != 1) return value;
    final season = seasons.single;
    if (RegExp(r'\bS0?' + season.toString() + r'\b', caseSensitive: false)
        .hasMatch(value)) {
      return value;
    }
    return '$value S${season.toString().padLeft(2, '0')}';
  }

  static String _episodeSubtitle(
    Iterable<MediaLibraryEpisode> episodes, {
    required bool isMovie,
  }) {
    final list = episodes.toList(growable: false);
    if (isMovie) {
      return list.length > 1 ? '电影 · ${list.length} 个版本' : '电影';
    }
    final count = list.length;
    if (count == 0) return '电视剧';
    final numbers = list
        .map((episode) => episode.episodeNumber)
        .whereType<int>()
        .where((episode) => episode > 0)
        .toSet()
        .toList()
      ..sort();
    final parts = <String>['$count 集'];
    if (numbers.length == 1) {
      parts.add('第 ${numbers.single} 集');
    } else if (numbers.length > 1) {
      parts.add('第 ${numbers.first}-${numbers.last} 集');
    }
    return parts.join(' · ');
  }

  static String _details({
    required Iterable<MediaLibraryEpisode> episodes,
    required double? rating,
    required String? mediaTypeLabel,
    String? releaseDate,
  }) {
    final list = episodes.toList(growable: false);
    final extensions = list
        .map((episode) =>
            p.extension(episode.name).replaceFirst('.', '').toUpperCase())
        .where((extension) => extension.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final totalSize = list.fold<int>(
      0,
      (sum, episode) => sum + (episode.size ?? episode.localItem?.size ?? 0),
    );
    DateTime? latest;
    for (final episode in list) {
      final modified = episode.modifiedAt ?? episode.localItem?.modified;
      if (modified != null && (latest == null || modified.isAfter(latest))) {
        latest = modified;
      }
    }
    final parts = <String>[
      if (extensions.isNotEmpty) extensions.join('/'),
      if (totalSize > 0) formatBytes(totalSize),
      if (latest != null) formatDate(latest),
      if (rating != null) '${rating.toStringAsFixed(1)} ★',
      if (mediaTypeLabel != null && mediaTypeLabel.isNotEmpty) mediaTypeLabel,
      if (_releaseYear(releaseDate) != null) _releaseYear(releaseDate)!,
    ];
    return parts.join(' · ');
  }

  static bool _episodeHasSubtitle(MediaLibraryEpisode episode) =>
      episode.subtitleRemotePaths.isNotEmpty ||
      episode.subtitleRemoteRefs.isNotEmpty ||
      episode.localItem?.subtitlePath?.isNotEmpty == true;

  static bool _isScraped(MediaLibrarySeries series) =>
      series.tmdbTitle?.trim().isNotEmpty == true ||
      series.tmdbPosterUrl?.trim().isNotEmpty == true ||
      series.posterCachePath?.trim().isNotEmpty == true ||
      series.tmdbRating != null;

  static String? _mediaTypeLabel(TmdbMediaType? type) => switch (type) {
        TmdbMediaType.movie => '电影',
        TmdbMediaType.tv => '电视剧',
        null => null,
      };

  static String? _releaseYear(String? value) {
    final match = RegExp(r'^(\d{4})').firstMatch(value?.trim() ?? '');
    return match?.group(1);
  }

  static IconData _categoryIcon(String label) {
    if (label == '动漫') return Icons.animation_outlined;
    if (label == '电视剧') return Icons.tv_outlined;
    if (label == '电影') return Icons.movie_outlined;
    return Icons.category_outlined;
  }

  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  static String formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

extension on Iterable<int?> {
  int? elementAtOrNull(int index) {
    if (index < 0 || index >= length) return null;
    return elementAt(index);
  }
}
