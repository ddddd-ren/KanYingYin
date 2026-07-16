enum TmdbMediaTypeMode { auto, movie, tv }

enum TmdbConfidenceMode { strict, standard, relaxed }

class TmdbScrapeOptions {
  final String language;
  final TmdbMediaTypeMode mediaTypeMode;
  final TmdbConfidenceMode confidenceMode;
  final bool overwriteTitle;
  final bool overwriteOverview;
  final bool overwritePoster;
  final bool fetchPoster;
  final bool fetchBackdrop;

  const TmdbScrapeOptions({
    required this.language,
    required this.mediaTypeMode,
    required this.confidenceMode,
    required this.overwriteTitle,
    required this.overwriteOverview,
    required this.overwritePoster,
    required this.fetchPoster,
    required this.fetchBackdrop,
  });

  const TmdbScrapeOptions.defaults()
      : language = 'zh-CN',
        mediaTypeMode = TmdbMediaTypeMode.auto,
        confidenceMode = TmdbConfidenceMode.standard,
        overwriteTitle = false,
        overwriteOverview = true,
        overwritePoster = true,
        fetchPoster = true,
        fetchBackdrop = true;

  double get minimumScore => switch (confidenceMode) {
        TmdbConfidenceMode.strict => 0.9,
        TmdbConfidenceMode.standard => 0.8,
        TmdbConfidenceMode.relaxed => 0.7,
      };

  double get minimumLead => switch (confidenceMode) {
        TmdbConfidenceMode.strict => 0.15,
        TmdbConfidenceMode.standard => 0.1,
        TmdbConfidenceMode.relaxed => 0.05,
      };

  factory TmdbScrapeOptions.fromMap(Object? value) {
    if (value is! Map) return const TmdbScrapeOptions.defaults();
    final map = Map<String, dynamic>.from(value);
    const defaults = TmdbScrapeOptions.defaults();
    return TmdbScrapeOptions(
      language: map['language']?.toString() ?? defaults.language,
      mediaTypeMode: _enumValue(
        TmdbMediaTypeMode.values,
        map['mediaTypeMode'],
        defaults.mediaTypeMode,
      ),
      confidenceMode: _enumValue(
        TmdbConfidenceMode.values,
        map['confidenceMode'],
        defaults.confidenceMode,
      ),
      overwriteTitle: map['overwriteTitle'] as bool? ?? defaults.overwriteTitle,
      overwriteOverview:
          map['overwriteOverview'] as bool? ?? defaults.overwriteOverview,
      overwritePoster:
          map['overwritePoster'] as bool? ?? defaults.overwritePoster,
      fetchPoster: map['fetchPoster'] as bool? ?? defaults.fetchPoster,
      fetchBackdrop: map['fetchBackdrop'] as bool? ?? defaults.fetchBackdrop,
    );
  }

  Map<String, dynamic> toMap() => {
        'language': language,
        'mediaTypeMode': mediaTypeMode.name,
        'confidenceMode': confidenceMode.name,
        'overwriteTitle': overwriteTitle,
        'overwriteOverview': overwriteOverview,
        'overwritePoster': overwritePoster,
        'fetchPoster': fetchPoster,
        'fetchBackdrop': fetchBackdrop,
      };

  TmdbScrapeOptions copyWith({
    String? language,
    TmdbMediaTypeMode? mediaTypeMode,
    TmdbConfidenceMode? confidenceMode,
    bool? overwriteTitle,
    bool? overwriteOverview,
    bool? overwritePoster,
    bool? fetchPoster,
    bool? fetchBackdrop,
  }) {
    return TmdbScrapeOptions(
      language: language ?? this.language,
      mediaTypeMode: mediaTypeMode ?? this.mediaTypeMode,
      confidenceMode: confidenceMode ?? this.confidenceMode,
      overwriteTitle: overwriteTitle ?? this.overwriteTitle,
      overwriteOverview: overwriteOverview ?? this.overwriteOverview,
      overwritePoster: overwritePoster ?? this.overwritePoster,
      fetchPoster: fetchPoster ?? this.fetchPoster,
      fetchBackdrop: fetchBackdrop ?? this.fetchBackdrop,
    );
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    return values.where((value) => value.name == raw).firstOrNull ?? fallback;
  }
}
