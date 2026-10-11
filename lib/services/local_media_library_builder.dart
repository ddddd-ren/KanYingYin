import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';
import 'package:path/path.dart' as p;

class LocalMediaLibraryBuilder {
  const LocalMediaLibraryBuilder();

  List<LocalMediaSeries> buildSeries(
    Iterable<LocalMediaIndexItem> items, {
    Map<String, String> sourceTitlesByMediaId = const <String, String>{},
    Map<String, List<String>> legacyTitlesByMediaId = const <String, List<String>>{},
  }) {
    final sourceItems = items.toList(growable: false);
    final indexedByPath = {
      for (final item in sourceItems) item.path: item,
    };
    final grouped = const LocalSeriesGrouper().group(
      sourceItems.map((item) => item.toFileItem()),
    );

    final series = grouped.expand((group) {
      final episodes = group.episodes
          .map((item) => indexedByPath[item.path])
          .whereType<LocalMediaIndexItem>()
          .toList(growable: false)
        ..sort(_compareEpisodes);
      final title = group.title.trim();
      final bySourceTitle = <String, List<LocalMediaIndexItem>>{};
      for (final episode in episodes) {
        final sourceTitle = sourceTitlesByMediaId[episode.id]?.trim();
        final displayTitle = sourceTitle?.isNotEmpty == true
            ? sourceTitle!
            : title.isEmpty
                ? _fallbackTitle(episode)
                : title;
        bySourceTitle.putIfAbsent(displayTitle, () => []).add(episode);
      }
      return bySourceTitle.entries.map((entry) => LocalMediaSeries(
            key: bySourceTitle.length == 1
                ? title.toLowerCase()
                : '${title.toLowerCase()}|source|${entry.value.first.id}',
            title: entry.key,
            legacyTitle: title,
            legacySeriesTitles: legacySeriesTitlesFor(
              entry.value.map((item) => item.id),
              legacyTitlesByMediaId,
            ),
            episodes: entry.value,
          ));
    }).toList();

    series.sort((a, b) {
      final modified = b.latestModified.compareTo(a.latestModified);
      if (modified != 0) return modified;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return series;
  }

  static List<String> legacySeriesTitlesFor(
    Iterable<String> mediaIds,
    Map<String, List<String>> titlesByMediaId,
  ) {
    final ids = mediaIds.toList(growable: false);
    if (ids.isEmpty) return const <String>[];
    return (titlesByMediaId[ids.first] ?? const <String>[])
        .where((title) => ids.every((id) =>
            (titlesByMediaId[id] ?? const <String>[]).any(
              (candidate) => candidate.toLowerCase() == title.toLowerCase(),
            )))
        .toList(growable: false);
  }

  String _fallbackTitle(LocalMediaIndexItem item) {
    return item.seriesName.trim().isEmpty
        ? p.basename(item.parentPath)
        : item.seriesName;
  }

  int _compareEpisodes(
    LocalMediaIndexItem a,
    LocalMediaIndexItem b,
  ) {
    final season = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
    if (season != 0) return season;
    final episode = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
    if (episode != 0) return episode;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

class LocalMediaSeries {
  final String key;
  final String title;
  final String? legacyTitle;
  final List<String> legacySeriesTitles;
  final int? seasonNumber;
  final List<LocalMediaIndexItem> episodes;

  const LocalMediaSeries({
    required this.key,
    required this.title,
    required this.episodes,
    this.legacyTitle,
    this.legacySeriesTitles = const <String>[],
    this.seasonNumber,
  });

  int get episodeCount => episodes.length;

  String get displayTitle {
    final season = seasonNumber;
    if (season != null && season > 0) {
      return '$title S${season.toString().padLeft(2, '0')}';
    }
    return title;
  }

  String? get cover {
    for (final item in episodes) {
      final value = item.cover;
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  DateTime get latestModified {
    if (episodes.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return episodes
        .map((item) => item.modified)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }
}
