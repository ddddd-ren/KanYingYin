class TmdbImageOverride {
  const TmdbImageOverride({
    this.poster,
    this.backdrop,
    this.seasonPosters = const <int, String>{},
    this.episodeStills = const <String, String>{},
  });

  final String? poster;
  final String? backdrop;
  final Map<int, String> seasonPosters;
  final Map<String, String> episodeStills;

  bool get isEmpty =>
      poster == null &&
      backdrop == null &&
      seasonPosters.isEmpty &&
      episodeStills.isEmpty;

  TmdbImageOverride copyWith({
    String? poster,
    String? backdrop,
    Map<int, String>? seasonPosters,
    Map<String, String>? episodeStills,
  }) {
    return TmdbImageOverride(
      poster: poster ?? this.poster,
      backdrop: backdrop ?? this.backdrop,
      seasonPosters: seasonPosters ?? this.seasonPosters,
      episodeStills: episodeStills ?? this.episodeStills,
    );
  }

  TmdbImageOverride clearPoster() => TmdbImageOverride(
        backdrop: backdrop,
        seasonPosters: seasonPosters,
        episodeStills: episodeStills,
      );

  TmdbImageOverride clearBackdrop() => TmdbImageOverride(
        poster: poster,
        seasonPosters: seasonPosters,
        episodeStills: episodeStills,
      );

  TmdbImageOverride clearSeasonPoster(int seasonNumber) {
    final values = <int, String>{...seasonPosters}..remove(seasonNumber);
    return TmdbImageOverride(
      poster: poster,
      backdrop: backdrop,
      seasonPosters: values,
      episodeStills: episodeStills,
    );
  }

  TmdbImageOverride clearEpisodeStill(int seasonNumber, int episodeNumber) {
    final values = <String, String>{...episodeStills}
      ..remove('$seasonNumber:$episodeNumber');
    return TmdbImageOverride(
      poster: poster,
      backdrop: backdrop,
      seasonPosters: seasonPosters,
      episodeStills: values,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (poster != null) 'poster': poster,
        if (backdrop != null) 'backdrop': backdrop,
        if (seasonPosters.isNotEmpty)
          'seasonPosters': <String, String>{
            for (final entry in seasonPosters.entries)
              entry.key.toString(): entry.value,
          },
        if (episodeStills.isNotEmpty) 'episodeStills': episodeStills,
      };

  factory TmdbImageOverride.fromJson(Object? raw) {
    if (raw is! Map) return const TmdbImageOverride();
    final seasons = <int, String>{};
    final seasonRaw = raw['seasonPosters'];
    if (seasonRaw is Map) {
      for (final entry in seasonRaw.entries) {
        final season = int.tryParse(entry.key.toString());
        final path = entry.value?.toString().trim() ?? '';
        if (season != null && season > 0 && path.isNotEmpty) {
          seasons[season] = path;
        }
      }
    }
    final episodes = <String, String>{};
    final episodeRaw = raw['episodeStills'];
    if (episodeRaw is Map) {
      for (final entry in episodeRaw.entries) {
        final key = entry.key.toString().trim();
        final path = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && path.isNotEmpty) episodes[key] = path;
      }
    }
    return TmdbImageOverride(
      poster: _asString(raw['poster']),
      backdrop: _asString(raw['backdrop']),
      seasonPosters: Map<int, String>.unmodifiable(seasons),
      episodeStills: Map<String, String>.unmodifiable(episodes),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TmdbImageOverride &&
            poster == other.poster &&
            backdrop == other.backdrop &&
            _mapEquals(seasonPosters, other.seasonPosters) &&
            _mapEquals(episodeStills, other.episodeStills);
  }

  @override
  int get hashCode => Object.hash(
        poster,
        backdrop,
        Object.hashAll(seasonPosters.entries),
        Object.hashAll(episodeStills.entries),
      );
}

String? _asString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _mapEquals<K, V>(Map<K, V> first, Map<K, V> second) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;
  for (final entry in first.entries) {
    if (second[entry.key] != entry.value) return false;
  }
  return true;
}
