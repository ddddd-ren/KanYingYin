import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

class MediaLibraryQuery {
  const MediaLibraryQuery();

  List<MediaLibrarySeries> apply({
    required Iterable<MediaLibrarySeries> series,
    String sourceId = 'all',
    String keyword = '',
    Set<String> selectedGenres = const <String>{},
    Set<String> selectedTags = const <String>{},
    Map<String, Iterable<String>> extraTagsBySeries =
        const <String, Iterable<String>>{},
  }) {
    final query = keyword.trim().toLowerCase();
    return series.where((item) {
      if (sourceId != 'all' && item.sourceId != sourceId) return false;
      if (query.isNotEmpty && !item.title.toLowerCase().contains(query)) {
        return false;
      }
      if (selectedGenres.isNotEmpty &&
          !item.genres.any(selectedGenres.contains)) {
        return false;
      }
      if (selectedTags.isNotEmpty &&
          !tagsForSeries(item, extraTags: extraTagsBySeries)
              .any(selectedTags.contains)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<String> availableGenres(
    Iterable<MediaLibrarySeries> series, {
    String sourceId = 'all',
  }) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(item.genres);
      }
    }
    return values.toList(growable: false)..sort();
  }

  Set<String> retainAvailableGenres(
    Set<String> selected,
    Iterable<String> available,
  ) {
    return selected.intersection(available.toSet());
  }

  List<String> availableTags(
    Iterable<MediaLibrarySeries> series, {
    String sourceId = 'all',
    Map<String, Iterable<String>> extraTagsBySeries =
        const <String, Iterable<String>>{},
  }) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(tagsForSeries(item, extraTags: extraTagsBySeries));
      }
    }
    return values.toList(growable: false)..sort();
  }

  List<String> availableCategories(
    Iterable<MediaLibrarySeries> series, {
    String sourceId = 'all',
  }) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(categoriesForSeries(item));
      }
    }
    return values.toList(growable: false)..sort();
  }

  List<String> availableCustomTags(
    Iterable<MediaLibrarySeries> series, {
    String sourceId = 'all',
    Map<String, Iterable<String>> customTagsBySeries =
        const <String, Iterable<String>>{},
  }) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(customTagsBySeries[item.seriesKey] ?? const <String>[]);
      }
    }
    return values.toList(growable: false)..sort();
  }

  List<String> tagsForSeries(
    MediaLibrarySeries item, {
    Map<String, Iterable<String>> extraTags =
        const <String, Iterable<String>>{},
  }) {
    final values = <String>{
      ...item.genres,
      ...categoriesForSeries(item),
      ...(extraTags[item.seriesKey] ?? const <String>[]),
    };
    values.removeWhere((value) => value.trim().isEmpty);
    return values.toList(growable: false);
  }

  List<String> categoriesForSeries(MediaLibrarySeries item) {
    var hasMovie = item.mediaType == TmdbMediaType.movie;
    var hasTvSeries = item.mediaType == TmdbMediaType.tv;
    var isAnimation = item.genres.any(_isAnimationGenre);
    for (final episode in item.episodes) {
      final metadata = episode.localItem?.tmdb;
      if (metadata == null) continue;
      switch (metadata.mediaType) {
        case TmdbMediaType.movie:
          hasMovie = true;
        case TmdbMediaType.tv:
          hasTvSeries = true;
      }
      if (metadata.genres.any(_isAnimationGenre)) {
        isAnimation = true;
      }
    }
    final categories = <String>[];
    if (hasMovie) categories.add('电影');
    if (isAnimation) categories.add('动漫');
    if (hasTvSeries) categories.add('电视剧');
    return categories;
  }

  bool _isAnimationGenre(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '动画' ||
        normalized == '动漫' ||
        normalized == 'animation' ||
        normalized == 'anime';
  }
}
