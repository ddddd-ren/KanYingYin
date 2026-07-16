import 'dart:io';

import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:path/path.dart' as p;

class LocalSubtitleMatcher {
  LocalSubtitleMatcher({
    LocalEpisodeParser? episodeParser,
  }) : _episodeParser = episodeParser ?? LocalEpisodeParser();

  final LocalEpisodeParser _episodeParser;

  static const subtitleExtensions = {
    '.ass',
    '.ssa',
    '.srt',
    '.vtt',
  };

  static const _subtitleDirectories = {
    'subs',
    'sub',
    'subtitle',
    'subtitles',
    '字幕',
    '字幕文件',
  };

  static bool isSupportedSubtitlePath(String path) {
    return subtitleExtensions.contains(p.extension(path).toLowerCase());
  }

  String? findForVideo(String videoPath) {
    final scored = _scoredSubtitleCandidates(videoPath)
        .where((candidate) => candidate.autoSelectable)
        .toList();
    if (scored.isEmpty) return null;

    scored.sort(_compareSubtitleScore);
    return scored.first.path;
  }

  List<String> findAllForVideo(String videoPath) {
    final scored = _scoredSubtitleCandidates(videoPath).toList();
    scored.sort(_compareSubtitleScore);
    return scored.map((candidate) => candidate.path).toList(growable: false);
  }

  List<_SubtitleScore> _scoredSubtitleCandidates(String videoPath) {
    final videoDir = p.dirname(videoPath);
    final videoBaseName = p.basenameWithoutExtension(videoPath);
    final candidates = _subtitleCandidates(videoDir).toList();
    if (candidates.isEmpty) return <_SubtitleScore>[];

    final videoEpisode = _episodeParser.parse(videoPath);
    final scored = <_SubtitleScore>[];
    for (final candidate in candidates) {
      final sameName = _isSameName(candidate.path, videoBaseName);
      final episodeMatch = videoEpisode != null &&
          _matchesEpisode(
            videoEpisodePath: videoPath,
            subtitlePath: candidate.path,
          );
      final inSubtitleDirectory = _isInSubtitleDirectory(candidate.path);
      scored.add(_SubtitleScore(
        path: candidate.path,
        priority: _subtitlePriority(
          sameName: sameName,
          inSubtitleDirectory: inSubtitleDirectory,
          episodeMatch: episodeMatch,
        ),
        score: _scoreSubtitle(
          videoPath: videoPath,
          subtitlePath: candidate.path,
          sameName: sameName,
          inSubtitleDirectory: inSubtitleDirectory,
          episodeMatch: episodeMatch,
        ),
        autoSelectable: sameName || episodeMatch,
      ));
    }

    return scored;
  }

  bool _matchesEpisode({
    required String videoEpisodePath,
    required String subtitlePath,
  }) {
    final videoEpisode = _episodeParser.parse(videoEpisodePath);
    final subtitleEpisode = _episodeParser.parse(subtitlePath);
    if (videoEpisode == null || subtitleEpisode == null) return false;
    if (subtitleEpisode.episodeNumber != videoEpisode.episodeNumber) {
      return false;
    }
    if (videoEpisode.seasonNumber != null &&
        subtitleEpisode.seasonNumber != null &&
        videoEpisode.seasonNumber != subtitleEpisode.seasonNumber) {
      return false;
    }
    return true;
  }

  int _compareSubtitleScore(_SubtitleScore a, _SubtitleScore b) {
    final priority = a.priority.compareTo(b.priority);
    if (priority != 0) return priority;

    final score = b.score.compareTo(a.score);
    if (score != 0) return score;

    return a.path.compareTo(b.path);
  }

  int _subtitlePriority({
    required bool sameName,
    required bool inSubtitleDirectory,
    required bool episodeMatch,
  }) {
    if (sameName) return 0;
    if (inSubtitleDirectory) return 1;
    if (episodeMatch) return 2;
    return 3;
  }

  bool _isSameName(String subtitlePath, String baseName) {
    return p.basenameWithoutExtension(subtitlePath).toLowerCase() ==
        baseName.toLowerCase();
  }

  bool _isInSubtitleDirectory(String subtitlePath) {
    final parentName = p.basename(p.dirname(subtitlePath)).toLowerCase();
    return _subtitleDirectories.contains(parentName);
  }

  Iterable<_SubtitleCandidate> _subtitleCandidates(String videoDir) sync* {
    yield* _subtitleFilesIn(videoDir);

    try {
      for (final entry in Directory(videoDir).listSync(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = p.basename(entry.path).toLowerCase();
        if (!_subtitleDirectories.contains(name)) continue;
        yield* _subtitleFilesIn(entry.path);
      }
    } catch (_) {
      return;
    }
  }

  Iterable<_SubtitleCandidate> _subtitleFilesIn(String dirPath) sync* {
    try {
      for (final entry in Directory(dirPath).listSync(followLinks: false)) {
        if (entry is! File) continue;
        if (!isSupportedSubtitlePath(entry.path)) continue;
        yield _SubtitleCandidate(path: entry.path);
      }
    } catch (_) {
      return;
    }
  }

  int _scoreSubtitle({
    required String videoPath,
    required String subtitlePath,
    required bool sameName,
    required bool inSubtitleDirectory,
    required bool episodeMatch,
  }) {
    var score = 0;
    final videoDir = p.dirname(videoPath);
    if (sameName) {
      score += 100;
    }
    if (inSubtitleDirectory) {
      score += 60;
    }
    if (episodeMatch) {
      score += 50;
    }
    if (p.dirname(subtitlePath) == videoDir) {
      score += 30;
    }

    final videoEpisode = _episodeParser.parse(videoPath);
    final subtitleEpisode = _episodeParser.parse(subtitlePath);
    if (videoEpisode != null && subtitleEpisode != null) {
      if (_normalizeTitle(videoEpisode.seriesName) ==
          _normalizeTitle(subtitleEpisode.seriesName)) {
        score += 20;
      }
    }

    final name = p.basenameWithoutExtension(subtitlePath).toLowerCase();
    if (name.contains('sc') || name.contains('chs') || name.contains('gb')) {
      score += 6;
    }
    if (name.contains('zh') || name.contains('简')) {
      score += 5;
    }
    if (name.contains('tc') || name.contains('cht') || name.contains('繁')) {
      score += 3;
    }
    return score;
  }

  String _normalizeTitle(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\s._\-\[\]\(\)\u3000]+'), '');
  }
}

class _SubtitleCandidate {
  final String path;

  const _SubtitleCandidate({
    required this.path,
  });
}

class _SubtitleScore {
  final String path;
  final int priority;
  final int score;
  final bool autoSelectable;

  const _SubtitleScore({
    required this.path,
    required this.priority,
    required this.score,
    required this.autoSelectable,
  });
}
