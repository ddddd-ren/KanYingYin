import 'dart:math' as math;

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
    this.aliasMatched = false,
    this.titleSimilarity = 0,
    this.seasonEvidenceMatched = false,
    this.matchReason = '',
  });

  final TmdbMetadata metadata;
  final double score;
  final bool titleMatched;
  final bool yearMatched;
  final bool typeMatched;
  final bool aliasMatched;
  final double titleSimilarity;
  final bool seasonEvidenceMatched;
  final String matchReason;
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
    bool seasonEvidence = false,
  }) {
    final ranked = rank(
      queryTitle: queryTitle,
      queryYear: queryYear,
      expectedTypes: <TmdbMediaType>{expectedType},
      candidates: candidates,
      minimumScore: minimumScore,
      minimumLead: minimumLead,
      seasonEvidence: seasonEvidence,
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
    bool seasonEvidence = false,
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
          seasonEvidence,
        ),
      ));
    }

    // 只有基础分完全相同时才使用热度作为极小的稳定排序信号。
    scored.sort((left, right) {
      final scoreOrder = right.candidate.score.compareTo(left.candidate.score);
      if (scoreOrder != 0) return scoreOrder;
      final popularityOrder =
          (right.candidate.metadata.popularity ?? 0).compareTo(
        left.candidate.metadata.popularity ?? 0,
      );
      return popularityOrder != 0
          ? popularityOrder
          : left.index.compareTo(right.index);
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
    final mixedTypes = expectedTypes.contains(TmdbMediaType.movie) &&
        expectedTypes.contains(TmdbMediaType.tv) &&
        ranked.any(
          (candidate) => candidate.metadata.mediaType == TmdbMediaType.movie,
        ) &&
        ranked.any(
          (candidate) => candidate.metadata.mediaType == TmdbMediaType.tv,
        );
    final hasTitleEvidence = best.titleMatched || best.titleSimilarity >= 0.78;
    final conservativeTypeBoundary = mixedTypes && !seasonEvidence;
    final requiredLead = best.aliasMatched ? minimumLead * 0.75 : minimumLead;
    return TmdbRankedResult(
      candidates: ranked,
      shouldAutoMatch: best.typeMatched &&
          hasTitleEvidence &&
          best.score >= minimumScore &&
          best.score - secondScore >= requiredLead &&
          !conservativeTypeBoundary,
    );
  }

  TmdbRankedCandidate _rankCandidate(
    String queryTitle,
    int? queryYear,
    Set<TmdbMediaType> expectedTypes,
    TmdbMetadata candidate,
    bool seasonEvidence,
  ) {
    final query = _normalize(queryTitle);
    final title = _normalize(candidate.title);
    final original = _normalize(candidate.originalTitle ?? '');
    final aliases =
        candidate.aliases.map(_normalize).where((value) => value.isNotEmpty);
    final aliasSet = aliases.toSet();

    final primaryExact = query.isNotEmpty &&
        (query == title || (original.isNotEmpty && query == original));
    final aliasMatched = query.isNotEmpty && aliasSet.contains(query);
    final titleMatched = primaryExact || aliasMatched;
    final comparableTitles = <String>[
      title,
      if (original.isNotEmpty) original,
      ...aliasSet
    ];
    final titleSimilarity = comparableTitles
        .map((value) => _similarity(query, value))
        .fold<double>(0, math.max)
        .clamp(0.0, 1.0);

    var score = 0.0;
    if (primaryExact) {
      score += 0.62;
    } else if (aliasMatched) {
      score += 0.58;
    }
    final similarityWeight = titleMatched ? 0.28 : 0.70;
    score += math.min(similarityWeight, titleSimilarity * similarityWeight);

    final candidateYear = _year(candidate.releaseDate);
    var yearMatched = false;
    if (queryYear != null && candidateYear != null) {
      final difference = (queryYear - candidateYear).abs();
      if (difference == 0) {
        score += 0.16;
        yearMatched = true;
      } else if (difference == 1) {
        score += 0.08;
        yearMatched = true;
      } else if (difference >= 2) {
        score -= 0.12;
      }
    }

    final typeMatched = expectedTypes.contains(candidate.mediaType);
    score += typeMatched ? 0.14 : -0.50;
    final seasonEvidenceMatched =
        seasonEvidence && candidate.mediaType == TmdbMediaType.tv;
    if (seasonEvidenceMatched) score += 0.08;

    final reason = _reason(
      titleMatched: titleMatched,
      aliasMatched: aliasMatched,
      titleSimilarity: titleSimilarity,
      yearMatched: yearMatched,
      typeMatched: typeMatched,
      seasonEvidenceMatched: seasonEvidenceMatched,
      queryYear: queryYear,
      candidateYear: candidateYear,
    );
    return TmdbRankedCandidate(
      metadata: candidate,
      score: score.clamp(0.0, 1.0),
      titleMatched: titleMatched,
      yearMatched: yearMatched,
      typeMatched: typeMatched,
      aliasMatched: aliasMatched,
      titleSimilarity: titleSimilarity,
      seasonEvidenceMatched: seasonEvidenceMatched,
      matchReason: reason,
    );
  }

  String _reason({
    required bool titleMatched,
    required bool aliasMatched,
    required double titleSimilarity,
    required bool yearMatched,
    required bool typeMatched,
    required bool seasonEvidenceMatched,
    required int? queryYear,
    required int? candidateYear,
  }) {
    final parts = <String>[];
    if (aliasMatched) {
      parts.add('别名匹配');
    } else if (titleMatched) {
      parts.add('标题匹配');
    } else if (titleSimilarity >= 0.78) {
      parts.add('标题相似');
    }
    if (yearMatched) {
      parts.add('年份匹配');
    } else if (queryYear != null && candidateYear != null) {
      final difference = (queryYear - candidateYear).abs();
      if (difference >= 2) parts.add('年份差异');
    }
    parts.add(typeMatched ? '类型匹配' : '类型冲突');
    if (seasonEvidenceMatched) parts.add('季集证据匹配');
    return parts.join(' · ');
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
  }

  double _similarity(String query, String candidate) {
    if (query.isEmpty || candidate.isEmpty) return 0;
    if (query == candidate) return 1;
    final queryTokens = _tokens(query);
    final candidateTokens = _tokens(candidate);
    final union = <String>{...queryTokens, ...candidateTokens};
    final intersection = queryTokens.intersection(candidateTokens);
    final jaccard = union.isEmpty ? 0.0 : intersection.length / union.length;
    final contains = query.contains(candidate) || candidate.contains(query)
        ? math.min(query.length, candidate.length) /
            math.max(query.length, candidate.length)
        : 0.0;
    final cjk = _cjkSimilarity(query, candidate);
    return math.max(jaccard, math.max(contains, cjk));
  }

  Set<String> _tokens(String value) {
    return RegExp(r'[a-z0-9]+|[\u4e00-\u9fff]')
        .allMatches(value)
        .map((match) => match.group(0)!)
        .toSet();
  }

  double _cjkSimilarity(String query, String candidate) {
    final queryCjk = query.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
    final candidateCjk = candidate.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
    if (queryCjk.isEmpty || candidateCjk.isEmpty) return 0;
    var longest = 0;
    for (var start = 0; start < queryCjk.length; start++) {
      for (var end = start + 1; end <= queryCjk.length; end++) {
        if (candidateCjk.contains(queryCjk.substring(start, end))) {
          longest = math.max(longest, end - start);
        }
      }
    }
    return longest / math.max(queryCjk.length, candidateCjk.length);
  }

  int? _year(String? date) {
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }
}
