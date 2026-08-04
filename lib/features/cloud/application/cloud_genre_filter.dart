import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';

class CloudGenreFilter {
  const CloudGenreFilter();

  List<String> availableGenres(Iterable<CloudMediaIndexItem> items) {
    final genres = <String>{};
    for (final item in items) {
      for (final genre in item.tmdbGenres) {
        final normalized = genre.trim();
        if (normalized.isNotEmpty) genres.add(normalized);
      }
    }
    return genres.toList(growable: false)..sort();
  }

  List<CloudMediaIndexItem> apply(
    Iterable<CloudMediaIndexItem> items,
    Set<String> selectedGenres, {
    Iterable<String> Function(CloudMediaIndexItem item)? customTagsFor,
  }) {
    if (selectedGenres.isEmpty) return items.toList(growable: false);
    return items
        .where(
          (item) =>
              item.tmdbGenres.any(
                (genre) => selectedGenres.contains(genre.trim()),
              ) ||
              customTagsFor?.call(item).any(
                        (tag) => selectedGenres.contains(tag.trim()),
                      ) ==
                  true,
        )
        .toList(growable: false);
  }

  Set<String> retainAvailable(
    Set<String> selectedGenres,
    Iterable<String> availableGenres,
  ) {
    return selectedGenres.intersection(availableGenres.toSet());
  }
}
