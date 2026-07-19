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

class TmdbRankedCandidate {
  const TmdbRankedCandidate({
    required this.metadata,
    required this.score,
    required this.titleMatched,
    required this.yearMatched,
    required this.typeMatched,
  });

  final TmdbMetadata metadata;
  final double score;
  final bool titleMatched;
  final bool yearMatched;
  final bool typeMatched;
}

class TmdbRankedResult {
  const TmdbRankedResult({
    required this.candidates,
    required this.shouldAutoMatch,
  });

  final List<TmdbRankedCandidate> candidates;
  final bool shouldAutoMatch;

  TmdbRankedCandidate? get best => candidates.firstOrNull;
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
    final ranked = rank(
      queryTitle: queryTitle,
      queryYear: queryYear,
      expectedTypes: <TmdbMediaType>{expectedType},
      candidates: candidates,
      minimumScore: minimumScore,
      minimumLead: minimumLead,
    );
    final best = ranked.best;
    return TmdbMatchResult(
      best: best?.metadata,
      confidence: best?.score ?? 0,
      shouldAutoMatch: ranked.shouldAutoMatch,
    );
  }

  TmdbRankedResult rank({
    required String queryTitle,
    required Set<TmdbMediaType> expectedTypes,
    required List<TmdbMetadata> candidates,
    int? queryYear,
    double minimumScore = 0.8,
    double minimumLead = 0.1,
  }) {
    final scored = <({int index, TmdbRankedCandidate candidate})>[];
    for (var index = 0; index < candidates.length; index++) {
      scored.add((
        index: index,
        candidate: _rankCandidate(
          queryTitle,
          queryYear,
          expectedTypes,
          candidates[index],
        ),
      ));
    }
    scored.sort((left, right) {
      final scoreOrder = right.candidate.score.compareTo(left.candidate.score);
      return scoreOrder != 0 ? scoreOrder : left.index.compareTo(right.index);
    });
    final ranked = List<TmdbRankedCandidate>.unmodifiable(
      scored.map((entry) => entry.candidate),
    );
    if (ranked.isEmpty) {
      return const TmdbRankedResult(
        candidates: <TmdbRankedCandidate>[],
        shouldAutoMatch: false,
      );
    }
    final best = ranked.first;
    final secondScore = ranked.length > 1 ? ranked[1].score : 0.0;
    return TmdbRankedResult(
      candidates: ranked,
      shouldAutoMatch: best.typeMatched &&
          best.score >= minimumScore &&
          best.score - secondScore >= minimumLead,
    );
  }

  TmdbRankedCandidate _rankCandidate(
    String queryTitle,
    int? queryYear,
    Set<TmdbMediaType> expectedTypes,
    TmdbMetadata candidate,
  ) {
    final query = _normalize(queryTitle);
    final title = _normalize(candidate.title);
    final original = _normalize(candidate.originalTitle ?? '');
    var score = 0.0;
    var titleMatched = false;
    if (query.isNotEmpty &&
        (query == title || (original.isNotEmpty && query == original))) {
      score += 0.65;
      titleMatched = true;
    } else if (query.isNotEmpty &&
        title.isNotEmpty &&
        (title.contains(query) || query.contains(title))) {
      score += 0.4;
      titleMatched = true;
    }

    final candidateYear = _year(candidate.releaseDate);
    var yearMatched = false;
    if (queryYear != null && candidateYear != null) {
      final difference = (queryYear - candidateYear).abs();
      if (difference == 0) {
        score += 0.2;
        yearMatched = true;
      } else if (difference == 1) {
        score += 0.1;
        yearMatched = true;
      }
    }

    final typeMatched = expectedTypes.contains(candidate.mediaType);
    score += typeMatched ? 0.15 : -0.4;
    return TmdbRankedCandidate(
      metadata: candidate,
      score: score.clamp(0.0, 1.0),
      titleMatched: titleMatched,
      yearMatched: yearMatched,
      typeMatched: typeMatched,
    );
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
