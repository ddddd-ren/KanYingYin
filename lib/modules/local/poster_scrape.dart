import 'package:kanyingyin/modules/local/local_file_item.dart';

enum PosterScrapePhase {
  preparing,
  searching,
  downloading,
}

class PosterScrapeProgress {
  final PosterScrapePhase phase;
  final int current;
  final int total;
  final String fileName;
  final double progress;

  const PosterScrapeProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.fileName,
    required this.progress,
  });

  String get label {
    switch (phase) {
      case PosterScrapePhase.preparing:
        return '准备刮削';
      case PosterScrapePhase.searching:
        return '正在搜索 $current/$total';
      case PosterScrapePhase.downloading:
        return '正在下载 $current/$total';
    }
  }
}

class PosterScrapeResult {
  final int success;
  final int failed;
  final int skipped;
  final int total;

  const PosterScrapeResult({
    required this.success,
    required this.failed,
    required this.skipped,
    required this.total,
  });

  static const empty = PosterScrapeResult(
    success: 0,
    failed: 0,
    skipped: 0,
    total: 0,
  );

  Map<String, int> toMap() {
    return {
      'success': success,
      'failed': failed,
      'skipped': skipped,
      'total': total,
    };
  }
}

typedef PosterScrapeProgressCallback = void Function(
  PosterScrapeProgress progress,
);

extension LocalPosterTargets on Iterable<LocalFileItem> {
  List<LocalFileItem> get videosWithoutCover {
    return where((item) => item.isVideo && item.needsOnlinePoster).toList();
  }
}

extension LocalPosterTarget on LocalFileItem {
  bool get needsOnlinePoster {
    final currentCover = cover;
    if (currentCover == null || currentCover.isEmpty) return true;
    return currentCover
        .split(RegExp(r'[\\/]'))
        .any((segment) => segment == '.kanyingyin_thumbs');
  }
}
