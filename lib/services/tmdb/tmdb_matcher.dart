import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

class TmdbMatchResult {
  final TmdbMetadata? best;
  final double confidence;
  final bool shouldAutoMatch;

  const TmdbMatchResult({
    required this.best,
    required this.confidence,
    required this.shouldAutoMatch,
  });
}

class TmdbMatcher {
  const TmdbMatcher();

  TmdbMatchResult choose({
    required String queryTitle,
    required TmdbMediaType expectedType,
    required List<TmdbMetadata> candidates,
    int? queryYear,
    double minimumScore = 0.8,
    double minimumLead = 0.1,
  }) {
    if (candidates.isEmpty) {
      return const TmdbMatchResult(
        best: null,
        confidence: 0,
        shouldAutoMatch: false,
      );
    }

    final scored = candidates
        .map((candidate) => MapEntry(
              candidate,
              _score(queryTitle, queryYear, expectedType, candidate),
            ))
        .toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final best = scored.first;
    final secondScore = scored.length > 1 ? scored[1].value : 0.0;
    return TmdbMatchResult(
      best: best.key,
      confidence: best.value,
      shouldAutoMatch: best.key.mediaType == expectedType &&
          best.value >= minimumScore &&
          best.value - secondScore >= minimumLead,
    );
  }

  double _score(
    String queryTitle,
    int? queryYear,
    TmdbMediaType expectedType,
    TmdbMetadata candidate,
  ) {
    final query = _normalize(queryTitle);
    final title = _normalize(candidate.title);
    final original = _normalize(candidate.originalTitle ?? '');
    var score = 0.0;
    if (query == title || (original.isNotEmpty && query == original)) {
      score += 0.65;
    } else if (title.contains(query) || query.contains(title)) {
      score += 0.4;
    }

    final candidateYear = _year(candidate.releaseDate);
    if (queryYear != null && candidateYear != null) {
      final difference = (queryYear - candidateYear).abs();
      if (difference == 0) {
        score += 0.2;
      } else if (difference == 1) {
        score += 0.1;
      }
    }

    score += candidate.mediaType == expectedType ? 0.15 : -0.4;
    return score.clamp(0.0, 1.0);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
  }

  int? _year(String? date) {
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }
}
