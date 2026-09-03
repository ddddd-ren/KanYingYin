part of '../cloud_resources_controller.dart';

/// 自动整理：按 TMDB 规则批量整理当前来源。
mixin _CloudAutoOrganizeMixin on _CloudResourcesControllerBase {
  Future<CloudResourceAutoOrganizeSummary> autoOrganizeSelectedSource({
    void Function(CloudResourceAutoOrganizeProgress progress)? onProgress,
  }) async {
    final source = selectedSource;
    final coordinator = _tmdbCoordinator;
    if (source == null || coordinator == null) {
      throw StateError('当前没有可整理的网盘来源');
    }
    if (!coordinator.hasApiKey) {
      throw StateError('请先在设置中填写 TMDB API Key');
    }
    if (coordinator.isScraping) {
      throw StateError('当前目录正在刮削，请稍后再试');
    }
    if (autoOrganizing) throw StateError('自动整理正在进行');

    autoOrganizing = true;
    _notify();
    final client = _providerRegistry.createClient(source, _credentialStore);
    try {
      final discovery = await _autoOrganizer.discover(
        source: source,
        client: client,
        onProgress: (scannedDirectories, discoveredCandidates) {
          onProgress?.call(
            CloudResourceAutoOrganizeProgress(
              phase: CloudResourceAutoOrganizePhase.scanning,
              scannedDirectories: scannedDirectories,
              discoveredTargets: discoveredCandidates,
              completedTargets: 0,
              totalTargets: 0,
            ),
          );
        },
      );
      final targets = <CloudResourceTmdbTarget>[];
      var matched = 0;
      var skipped = 0;
      final now = DateTime.now();
      for (final target in discovery.candidates) {
        try {
          final application = await coordinator.applySeriesRule(target);
          if (application != null) {
            matched++;
            continue;
          }
        } on Object {
          // 规则读取失败时继续使用原有 TMDB 整理流程。
        }
        final record = coordinator.records[target.stableKey];
        final sameName = record?.displayName == target.displayName;
        final cachedMatched = record?.status == CloudResourceTmdbStatus.matched;
        final recentlyUnmatched =
            record?.status == CloudResourceTmdbStatus.unmatched &&
                record!.checkedAt
                    .add(CloudResourceTmdbCoordinator.unmatchedRetryInterval)
                    .isAfter(now);
        if ((sameName && (cachedMatched || recentlyUnmatched)) ||
            coordinator.scrapingKeys.contains(target.stableKey)) {
          skipped++;
        } else {
          targets.add(target);
        }
      }

      var completed = matched;
      var pending = 0;
      var noResult = 0;
      var failed = discovery.failedDirectories;
      final totalTargets = matched + targets.length;
      onProgress?.call(
        CloudResourceAutoOrganizeProgress(
          phase: CloudResourceAutoOrganizePhase.scraping,
          scannedDirectories: discovery.scannedDirectories,
          discoveredTargets: discovery.candidates.length,
          completedTargets: completed,
          totalTargets: totalTargets,
        ),
      );
      for (final target in targets) {
        try {
          final outcome = await coordinator.scrape(target);
          if (outcome.selected != null) {
            matched++;
          } else if (outcome.candidates.isNotEmpty) {
            pending++;
          } else {
            noResult++;
          }
        } on Object {
          failed++;
        } finally {
          completed++;
          onProgress?.call(
            CloudResourceAutoOrganizeProgress(
              phase: CloudResourceAutoOrganizePhase.scraping,
              scannedDirectories: discovery.scannedDirectories,
              discoveredTargets: discovery.candidates.length,
              completedTargets: completed,
              totalTargets: totalTargets,
            ),
          );
        }
      }
      return CloudResourceAutoOrganizeSummary(
        matched: matched,
        pending: pending,
        noResult: noResult,
        failed: failed,
        skipped: skipped,
      );
    } finally {
      await client.close();
      autoOrganizing = false;
      _notify();
    }
  }
}
