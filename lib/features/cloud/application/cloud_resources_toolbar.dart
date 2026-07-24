enum CloudToolbarAction { autoOrganize, scrape, removeSource }

class CloudResourcesToolbarState {
  const CloudResourcesToolbarState({
    required this.canChangeSource,
    required this.canRefresh,
    required this.canAutoOrganize,
    required this.canScrape,
    required this.canRemoveSource,
  });

  final bool canChangeSource;
  final bool canRefresh;
  final bool canAutoOrganize;
  final bool canScrape;
  final bool canRemoveSource;
}

/// 集中维护网盘媒体库工具栏的操作互斥规则。
class CloudResourcesToolbarPolicy {
  const CloudResourcesToolbarPolicy();

  CloudResourcesToolbarState evaluate({
    required bool hasSelectedSource,
    required bool loading,
    required bool scanning,
    required bool batchScraping,
    required bool autoOrganizing,
    required bool tmdbBusy,
  }) {
    final sourceIdle = hasSelectedSource && !loading && !scanning;
    return CloudResourcesToolbarState(
      canChangeSource: !loading && !autoOrganizing,
      canRefresh: sourceIdle && !autoOrganizing,
      canAutoOrganize:
          sourceIdle && !batchScraping && !autoOrganizing && !tmdbBusy,
      canScrape: sourceIdle && !batchScraping && !autoOrganizing,
      canRemoveSource: sourceIdle && !autoOrganizing,
    );
  }
}
