import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

class MediaLibraryQuery {
  const MediaLibraryQuery();

  List<MediaLibrarySeries> apply({
    required Iterable<MediaLibrarySeries> series,
    String sourceId = 'all',
    String keyword = '',
    Set<String> selectedGenres = const <String>{},
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
}
