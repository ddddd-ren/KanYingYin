enum TmdbMediaTypeMode { auto, movie, tv }

enum TmdbConfidenceMode { strict, standard, relaxed }

class TmdbScrapeOptions {
  final String language;
  final TmdbMediaTypeMode mediaTypeMode;
  final TmdbConfidenceMode confidenceMode;
  final bool overwriteTitle;
  final bool overwriteOverview;
  final bool overwritePoster;
  final bool scrapeEpisodeNames;
  final bool fetchPoster;
  final bool fetchBackdrop;
  final int maximumSearchPages;
  final int maximumAliasCandidates;

  const TmdbScrapeOptions({
    required this.language,
    required this.mediaTypeMode,
    required this.confidenceMode,
    required this.overwriteTitle,
    required this.overwriteOverview,
    required this.overwritePoster,
    required this.scrapeEpisodeNames,
    required this.fetchPoster,
    required this.fetchBackdrop,
    this.maximumSearchPages = 3,
    this.maximumAliasCandidates = 20,
  });

  const TmdbScrapeOptions.defaults()
      : language = 'zh-CN',
        mediaTypeMode = TmdbMediaTypeMode.auto,
        confidenceMode = TmdbConfidenceMode.standard,
        overwriteTitle = false,
        overwriteOverview = true,
        overwritePoster = true,
        scrapeEpisodeNames = true,
        fetchPoster = true,
        fetchBackdrop = true,
        maximumSearchPages = 3,
        maximumAliasCandidates = 20;

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
      scrapeEpisodeNames:
          map['scrapeEpisodeNames'] as bool? ?? defaults.scrapeEpisodeNames,
      fetchPoster: map['fetchPoster'] as bool? ?? defaults.fetchPoster,
      fetchBackdrop: map['fetchBackdrop'] as bool? ?? defaults.fetchBackdrop,
      maximumSearchPages: _positiveInt(
        map['maximumSearchPages'],
        defaults.maximumSearchPages,
      ),
      maximumAliasCandidates: _positiveInt(
        map['maximumAliasCandidates'],
        defaults.maximumAliasCandidates,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'language': language,
        'mediaTypeMode': mediaTypeMode.name,
        'confidenceMode': confidenceMode.name,
        'overwriteTitle': overwriteTitle,
        'overwriteOverview': overwriteOverview,
        'overwritePoster': overwritePoster,
        'scrapeEpisodeNames': scrapeEpisodeNames,
        'fetchPoster': fetchPoster,
        'fetchBackdrop': fetchBackdrop,
        'maximumSearchPages': maximumSearchPages,
        'maximumAliasCandidates': maximumAliasCandidates,
      };

  TmdbScrapeOptions copyWith({
    String? language,
    TmdbMediaTypeMode? mediaTypeMode,
    TmdbConfidenceMode? confidenceMode,
    bool? overwriteTitle,
    bool? overwriteOverview,
    bool? overwritePoster,
    bool? scrapeEpisodeNames,
    bool? fetchPoster,
    bool? fetchBackdrop,
    int? maximumSearchPages,
    int? maximumAliasCandidates,
  }) {
    return TmdbScrapeOptions(
      language: language ?? this.language,
      mediaTypeMode: mediaTypeMode ?? this.mediaTypeMode,
      confidenceMode: confidenceMode ?? this.confidenceMode,
      overwriteTitle: overwriteTitle ?? this.overwriteTitle,
      overwriteOverview: overwriteOverview ?? this.overwriteOverview,
      overwritePoster: overwritePoster ?? this.overwritePoster,
      scrapeEpisodeNames: scrapeEpisodeNames ?? this.scrapeEpisodeNames,
      fetchPoster: fetchPoster ?? this.fetchPoster,
      fetchBackdrop: fetchBackdrop ?? this.fetchBackdrop,
      maximumSearchPages: maximumSearchPages ?? this.maximumSearchPages,
      maximumAliasCandidates:
          maximumAliasCandidates ?? this.maximumAliasCandidates,
    );
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    Object? raw,
    T fallback,
  ) {
    return values.where((value) => value.name == raw).firstOrNull ?? fallback;
  }

  static int _positiveInt(Object? value, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed == null || parsed < 1 ? fallback : parsed;
  }
}
