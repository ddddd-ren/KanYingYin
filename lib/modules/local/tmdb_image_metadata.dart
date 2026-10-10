enum TmdbImageKind { poster, backdrop, still }

enum TmdbImageTargetKind { series, season, episode }

class TmdbImageCandidate {
  const TmdbImageCandidate({
    required this.filePath,
    required this.kind,
    this.language,
    this.width,
    this.height,
    this.voteAverage,
    this.voteCount,
  });

  final String filePath;
  final TmdbImageKind kind;
  final String? language;
  final int? width;
  final int? height;
  final double? voteAverage;
  final int? voteCount;

  String url({String size = 'w500'}) {
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      return filePath;
    }
    return 'https://image.tmdb.org/t/p/$size$filePath';
  }

  factory TmdbImageCandidate.fromJson(
    Map<String, dynamic> json,
    TmdbImageKind kind,
  ) {
    return TmdbImageCandidate(
      filePath: normalizeTmdbImagePath(json['file_path'] as String?) ?? '',
      kind: kind,
      language: _asString(json['iso_639_1']),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      voteAverage: _asDouble(json['vote_average']),
      voteCount: _asInt(json['vote_count']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'filePath': filePath,
        'kind': kind.name,
        if (language != null) 'language': language,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (voteAverage != null) 'voteAverage': voteAverage,
        if (voteCount != null) 'voteCount': voteCount,
      };
}

/// 将 TMDB 图片 URL 和 API 返回的 file_path 统一为可持久化的路径。
String? normalizeTmdbImagePath(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host != 'image.tmdb.org') {
    return normalized;
  }
  final match = RegExp(r'^/t/p/[^/]+(/.*)$').firstMatch(uri.path);
  return match?.group(1) ?? uri.path;
}

class TmdbImageSet {
  const TmdbImageSet({
    this.posters = const <TmdbImageCandidate>[],
    this.backdrops = const <TmdbImageCandidate>[],
    this.stills = const <TmdbImageCandidate>[],
  });

  final List<TmdbImageCandidate> posters;
  final List<TmdbImageCandidate> backdrops;
  final List<TmdbImageCandidate> stills;

  bool get isEmpty => posters.isEmpty && backdrops.isEmpty && stills.isEmpty;

  factory TmdbImageSet.fromJson(Map<String, dynamic> json) {
    List<TmdbImageCandidate> read(String key, TmdbImageKind kind) {
      final value = json[key];
      if (value is! List) return const <TmdbImageCandidate>[];
      final result = <TmdbImageCandidate>[];
      final seen = <String>{};
      for (final item in value.whereType<Map<Object?, Object?>>()) {
        final candidate = TmdbImageCandidate.fromJson(
          Map<String, dynamic>.from(item),
          kind,
        );
        if (candidate.filePath.isNotEmpty && seen.add(candidate.filePath)) {
          result.add(candidate);
        }
      }
      return List<TmdbImageCandidate>.unmodifiable(result);
    }

    return TmdbImageSet(
      posters: read('posters', TmdbImageKind.poster),
      backdrops: read('backdrops', TmdbImageKind.backdrop),
      stills: read('stills', TmdbImageKind.still),
    );
  }
}

String? _asString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
