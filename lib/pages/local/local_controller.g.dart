// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$LocalController on _LocalController, Store {
  Computed<int>? _$localLibraryVideoCountComputed;

  @override
  int get localLibraryVideoCount => (_$localLibraryVideoCountComputed ??=
          Computed<int>(() => super.localLibraryVideoCount,
              name: '_LocalController.localLibraryVideoCount'))
      .value;
  Computed<int>? _$mediaLibraryVideoCountComputed;

  @override
  int get mediaLibraryVideoCount => (_$mediaLibraryVideoCountComputed ??=
          Computed<int>(() => super.mediaLibraryVideoCount,
              name: '_LocalController.mediaLibraryVideoCount'))
      .value;
  Computed<int>? _$localLibrarySeriesCountComputed;

  @override
  int get localLibrarySeriesCount => (_$localLibrarySeriesCountComputed ??=
          Computed<int>(() => super.localLibrarySeriesCount,
              name: '_LocalController.localLibrarySeriesCount'))
      .value;
  Computed<List<LocalMediaSeries>>? _$localLibrarySeriesComputed;

  @override
  List<LocalMediaSeries> get localLibrarySeries =>
      (_$localLibrarySeriesComputed ??= Computed<List<LocalMediaSeries>>(
              () => super.localLibrarySeries,
              name: '_LocalController.localLibrarySeries'))
          .value;

  late final _$currentPathAtom =
      Atom(name: '_LocalController.currentPath', context: context);

  @override
  String get currentPath {
    _$currentPathAtom.reportRead();
    return super.currentPath;
  }

  @override
  set currentPath(String value) {
    _$currentPathAtom.reportWrite(value, super.currentPath, () {
      super.currentPath = value;
    });
  }

  late final _$itemsAtom =
      Atom(name: '_LocalController.items', context: context);

  @override
  ObservableList<LocalFileItem> get items {
    _$itemsAtom.reportRead();
    return super.items;
  }

  @override
  set items(ObservableList<LocalFileItem> value) {
    _$itemsAtom.reportWrite(value, super.items, () {
      super.items = value;
    });
  }

  late final _$isLoadingAtom =
      Atom(name: '_LocalController.isLoading', context: context);

  @override
  bool get isLoading {
    _$isLoadingAtom.reportRead();
    return super.isLoading;
  }

  @override
  set isLoading(bool value) {
    _$isLoadingAtom.reportWrite(value, super.isLoading, () {
      super.isLoading = value;
    });
  }

  late final _$errorMessageAtom =
      Atom(name: '_LocalController.errorMessage', context: context);

  @override
  String? get errorMessage {
    _$errorMessageAtom.reportRead();
    return super.errorMessage;
  }

  @override
  set errorMessage(String? value) {
    _$errorMessageAtom.reportWrite(value, super.errorMessage, () {
      super.errorMessage = value;
    });
  }

  late final _$sortByAtom =
      Atom(name: '_LocalController.sortBy', context: context);

  @override
  String get sortBy {
    _$sortByAtom.reportRead();
    return super.sortBy;
  }

  @override
  set sortBy(String value) {
    _$sortByAtom.reportWrite(value, super.sortBy, () {
      super.sortBy = value;
    });
  }

  late final _$sortAscendingAtom =
      Atom(name: '_LocalController.sortAscending', context: context);

  @override
  bool get sortAscending {
    _$sortAscendingAtom.reportRead();
    return super.sortAscending;
  }

  @override
  set sortAscending(bool value) {
    _$sortAscendingAtom.reportWrite(value, super.sortAscending, () {
      super.sortAscending = value;
    });
  }

  late final _$pathHistoryAtom =
      Atom(name: '_LocalController.pathHistory', context: context);

  @override
  ObservableList<String> get pathHistory {
    _$pathHistoryAtom.reportRead();
    return super.pathHistory;
  }

  @override
  set pathHistory(ObservableList<String> value) {
    _$pathHistoryAtom.reportWrite(value, super.pathHistory, () {
      super.pathHistory = value;
    });
  }

  late final _$mediaSourcesAtom =
      Atom(name: '_LocalController.mediaSources', context: context);

  @override
  ObservableList<LocalMediaSource> get mediaSources {
    _$mediaSourcesAtom.reportRead();
    return super.mediaSources;
  }

  @override
  set mediaSources(ObservableList<LocalMediaSource> value) {
    _$mediaSourcesAtom.reportWrite(value, super.mediaSources, () {
      super.mediaSources = value;
    });
  }

  late final _$isFetchingPostersAtom =
      Atom(name: '_LocalController.isFetchingPosters', context: context);

  @override
  bool get isFetchingPosters {
    _$isFetchingPostersAtom.reportRead();
    return super.isFetchingPosters;
  }

  @override
  set isFetchingPosters(bool value) {
    _$isFetchingPostersAtom.reportWrite(value, super.isFetchingPosters, () {
      super.isFetchingPosters = value;
    });
  }

  late final _$posterProgressAtom =
      Atom(name: '_LocalController.posterProgress', context: context);

  @override
  String get posterProgress {
    _$posterProgressAtom.reportRead();
    return super.posterProgress;
  }

  @override
  set posterProgress(String value) {
    _$posterProgressAtom.reportWrite(value, super.posterProgress, () {
      super.posterProgress = value;
    });
  }

  late final _$posterProgressValueAtom =
      Atom(name: '_LocalController.posterProgressValue', context: context);

  @override
  double get posterProgressValue {
    _$posterProgressValueAtom.reportRead();
    return super.posterProgressValue;
  }

  @override
  set posterProgressValue(double value) {
    _$posterProgressValueAtom.reportWrite(value, super.posterProgressValue, () {
      super.posterProgressValue = value;
    });
  }

  late final _$posterCurrentFileAtom =
      Atom(name: '_LocalController.posterCurrentFile', context: context);

  @override
  String get posterCurrentFile {
    _$posterCurrentFileAtom.reportRead();
    return super.posterCurrentFile;
  }

  @override
  set posterCurrentFile(String value) {
    _$posterCurrentFileAtom.reportWrite(value, super.posterCurrentFile, () {
      super.posterCurrentFile = value;
    });
  }

  late final _$posterCurrentAtom =
      Atom(name: '_LocalController.posterCurrent', context: context);

  @override
  int get posterCurrent {
    _$posterCurrentAtom.reportRead();
    return super.posterCurrent;
  }

  @override
  set posterCurrent(int value) {
    _$posterCurrentAtom.reportWrite(value, super.posterCurrent, () {
      super.posterCurrent = value;
    });
  }

  late final _$posterTotalAtom =
      Atom(name: '_LocalController.posterTotal', context: context);

  @override
  int get posterTotal {
    _$posterTotalAtom.reportRead();
    return super.posterTotal;
  }

  @override
  set posterTotal(int value) {
    _$posterTotalAtom.reportWrite(value, super.posterTotal, () {
      super.posterTotal = value;
    });
  }

  late final _$isFetchingMediaInfoAtom =
      Atom(name: '_LocalController.isFetchingMediaInfo', context: context);

  @override
  bool get isFetchingMediaInfo {
    _$isFetchingMediaInfoAtom.reportRead();
    return super.isFetchingMediaInfo;
  }

  @override
  set isFetchingMediaInfo(bool value) {
    _$isFetchingMediaInfoAtom.reportWrite(value, super.isFetchingMediaInfo, () {
      super.isFetchingMediaInfo = value;
    });
  }

  late final _$mediaInfoCurrentFileAtom =
      Atom(name: '_LocalController.mediaInfoCurrentFile', context: context);

  @override
  String get mediaInfoCurrentFile {
    _$mediaInfoCurrentFileAtom.reportRead();
    return super.mediaInfoCurrentFile;
  }

  @override
  set mediaInfoCurrentFile(String value) {
    _$mediaInfoCurrentFileAtom.reportWrite(value, super.mediaInfoCurrentFile,
        () {
      super.mediaInfoCurrentFile = value;
    });
  }

  late final _$mediaInfoCurrentAtom =
      Atom(name: '_LocalController.mediaInfoCurrent', context: context);

  @override
  int get mediaInfoCurrent {
    _$mediaInfoCurrentAtom.reportRead();
    return super.mediaInfoCurrent;
  }

  @override
  set mediaInfoCurrent(int value) {
    _$mediaInfoCurrentAtom.reportWrite(value, super.mediaInfoCurrent, () {
      super.mediaInfoCurrent = value;
    });
  }

  late final _$mediaInfoTotalAtom =
      Atom(name: '_LocalController.mediaInfoTotal', context: context);

  @override
  int get mediaInfoTotal {
    _$mediaInfoTotalAtom.reportRead();
    return super.mediaInfoTotal;
  }

  @override
  set mediaInfoTotal(int value) {
    _$mediaInfoTotalAtom.reportWrite(value, super.mediaInfoTotal, () {
      super.mediaInfoTotal = value;
    });
  }

  late final _$isFetchingThumbnailsAtom =
      Atom(name: '_LocalController.isFetchingThumbnails', context: context);

  @override
  bool get isFetchingThumbnails {
    _$isFetchingThumbnailsAtom.reportRead();
    return super.isFetchingThumbnails;
  }

  @override
  set isFetchingThumbnails(bool value) {
    _$isFetchingThumbnailsAtom.reportWrite(value, super.isFetchingThumbnails,
        () {
      super.isFetchingThumbnails = value;
    });
  }

  late final _$thumbnailCurrentFileAtom =
      Atom(name: '_LocalController.thumbnailCurrentFile', context: context);

  @override
  String get thumbnailCurrentFile {
    _$thumbnailCurrentFileAtom.reportRead();
    return super.thumbnailCurrentFile;
  }

  @override
  set thumbnailCurrentFile(String value) {
    _$thumbnailCurrentFileAtom.reportWrite(value, super.thumbnailCurrentFile,
        () {
      super.thumbnailCurrentFile = value;
    });
  }

  late final _$thumbnailCurrentAtom =
      Atom(name: '_LocalController.thumbnailCurrent', context: context);

  @override
  int get thumbnailCurrent {
    _$thumbnailCurrentAtom.reportRead();
    return super.thumbnailCurrent;
  }

  @override
  set thumbnailCurrent(int value) {
    _$thumbnailCurrentAtom.reportWrite(value, super.thumbnailCurrent, () {
      super.thumbnailCurrent = value;
    });
  }

  late final _$thumbnailTotalAtom =
      Atom(name: '_LocalController.thumbnailTotal', context: context);

  @override
  int get thumbnailTotal {
    _$thumbnailTotalAtom.reportRead();
    return super.thumbnailTotal;
  }

  @override
  set thumbnailTotal(int value) {
    _$thumbnailTotalAtom.reportWrite(value, super.thumbnailTotal, () {
      super.thumbnailTotal = value;
    });
  }

  late final _$localLibraryItemsAtom =
      Atom(name: '_LocalController.localLibraryItems', context: context);

  @override
  ObservableList<LocalMediaIndexItem> get localLibraryItems {
    _$localLibraryItemsAtom.reportRead();
    return super.localLibraryItems;
  }

  @override
  set localLibraryItems(ObservableList<LocalMediaIndexItem> value) {
    _$localLibraryItemsAtom.reportWrite(value, super.localLibraryItems, () {
      super.localLibraryItems = value;
    });
  }

  late final _$isScrapingTmdbAtom =
      Atom(name: '_LocalController.isScrapingTmdb', context: context);

  @override
  bool get isScrapingTmdb {
    _$isScrapingTmdbAtom.reportRead();
    return super.isScrapingTmdb;
  }

  @override
  set isScrapingTmdb(bool value) {
    _$isScrapingTmdbAtom.reportWrite(value, super.isScrapingTmdb, () {
      super.isScrapingTmdb = value;
    });
  }

  late final _$tmdbScrapeProgressAtom =
      Atom(name: '_LocalController.tmdbScrapeProgress', context: context);

  @override
  String get tmdbScrapeProgress {
    _$tmdbScrapeProgressAtom.reportRead();
    return super.tmdbScrapeProgress;
  }

  @override
  set tmdbScrapeProgress(String value) {
    _$tmdbScrapeProgressAtom.reportWrite(value, super.tmdbScrapeProgress, () {
      super.tmdbScrapeProgress = value;
    });
  }

  late final _$tmdbScrapeCurrentAtom =
      Atom(name: '_LocalController.tmdbScrapeCurrent', context: context);

  @override
  int get tmdbScrapeCurrent {
    _$tmdbScrapeCurrentAtom.reportRead();
    return super.tmdbScrapeCurrent;
  }

  @override
  set tmdbScrapeCurrent(int value) {
    _$tmdbScrapeCurrentAtom.reportWrite(value, super.tmdbScrapeCurrent, () {
      super.tmdbScrapeCurrent = value;
    });
  }

  late final _$tmdbScrapeTotalAtom =
      Atom(name: '_LocalController.tmdbScrapeTotal', context: context);

  @override
  int get tmdbScrapeTotal {
    _$tmdbScrapeTotalAtom.reportRead();
    return super.tmdbScrapeTotal;
  }

  @override
  set tmdbScrapeTotal(int value) {
    _$tmdbScrapeTotalAtom.reportWrite(value, super.tmdbScrapeTotal, () {
      super.tmdbScrapeTotal = value;
    });
  }

  late final _$isIndexingLibraryAtom =
      Atom(name: '_LocalController.isIndexingLibrary', context: context);

  @override
  bool get isIndexingLibrary {
    _$isIndexingLibraryAtom.reportRead();
    return super.isIndexingLibrary;
  }

  @override
  set isIndexingLibrary(bool value) {
    _$isIndexingLibraryAtom.reportWrite(value, super.isIndexingLibrary, () {
      super.isIndexingLibrary = value;
    });
  }

  late final _$libraryIndexCurrentFileAtom =
      Atom(name: '_LocalController.libraryIndexCurrentFile', context: context);

  @override
  String get libraryIndexCurrentFile {
    _$libraryIndexCurrentFileAtom.reportRead();
    return super.libraryIndexCurrentFile;
  }

  @override
  set libraryIndexCurrentFile(String value) {
    _$libraryIndexCurrentFileAtom
        .reportWrite(value, super.libraryIndexCurrentFile, () {
      super.libraryIndexCurrentFile = value;
    });
  }

  late final _$libraryIndexCurrentAtom =
      Atom(name: '_LocalController.libraryIndexCurrent', context: context);

  @override
  int get libraryIndexCurrent {
    _$libraryIndexCurrentAtom.reportRead();
    return super.libraryIndexCurrent;
  }

  @override
  set libraryIndexCurrent(int value) {
    _$libraryIndexCurrentAtom.reportWrite(value, super.libraryIndexCurrent, () {
      super.libraryIndexCurrent = value;
    });
  }

  late final _$libraryIndexTotalAtom =
      Atom(name: '_LocalController.libraryIndexTotal', context: context);

  @override
  int get libraryIndexTotal {
    _$libraryIndexTotalAtom.reportRead();
    return super.libraryIndexTotal;
  }

  @override
  set libraryIndexTotal(int value) {
    _$libraryIndexTotalAtom.reportWrite(value, super.libraryIndexTotal, () {
      super.libraryIndexTotal = value;
    });
  }

  late final _$libraryIndexProgressValueAtom = Atom(
      name: '_LocalController.libraryIndexProgressValue', context: context);

  @override
  double get libraryIndexProgressValue {
    _$libraryIndexProgressValueAtom.reportRead();
    return super.libraryIndexProgressValue;
  }

  @override
  set libraryIndexProgressValue(double value) {
    _$libraryIndexProgressValueAtom
        .reportWrite(value, super.libraryIndexProgressValue, () {
      super.libraryIndexProgressValue = value;
    });
  }

  late final _$libraryIndexProgressAtom =
      Atom(name: '_LocalController.libraryIndexProgress', context: context);

  @override
  String get libraryIndexProgress {
    _$libraryIndexProgressAtom.reportRead();
    return super.libraryIndexProgress;
  }

  @override
  set libraryIndexProgress(String value) {
    _$libraryIndexProgressAtom.reportWrite(value, super.libraryIndexProgress,
        () {
      super.libraryIndexProgress = value;
    });
  }

  late final _$libraryIndexSummaryAtom =
      Atom(name: '_LocalController.libraryIndexSummary', context: context);

  @override
  String get libraryIndexSummary {
    _$libraryIndexSummaryAtom.reportRead();
    return super.libraryIndexSummary;
  }

  @override
  set libraryIndexSummary(String value) {
    _$libraryIndexSummaryAtom.reportWrite(value, super.libraryIndexSummary, () {
      super.libraryIndexSummary = value;
    });
  }

  late final _$cancelLibraryIndexRequestedAtom = Atom(
      name: '_LocalController.cancelLibraryIndexRequested', context: context);

  @override
  bool get cancelLibraryIndexRequested {
    _$cancelLibraryIndexRequestedAtom.reportRead();
    return super.cancelLibraryIndexRequested;
  }

  @override
  set cancelLibraryIndexRequested(bool value) {
    _$cancelLibraryIndexRequestedAtom
        .reportWrite(value, super.cancelLibraryIndexRequested, () {
      super.cancelLibraryIndexRequested = value;
    });
  }

  late final _$libraryIndexFailuresAtom =
      Atom(name: '_LocalController.libraryIndexFailures', context: context);

  @override
  ObservableList<LocalMediaIndexFailure> get libraryIndexFailures {
    _$libraryIndexFailuresAtom.reportRead();
    return super.libraryIndexFailures;
  }

  @override
  set libraryIndexFailures(ObservableList<LocalMediaIndexFailure> value) {
    _$libraryIndexFailuresAtom.reportWrite(value, super.libraryIndexFailures,
        () {
      super.libraryIndexFailures = value;
    });
  }

  late final _$isFetchingDirCoversAtom =
      Atom(name: '_LocalController.isFetchingDirCovers', context: context);

  @override
  bool get isFetchingDirCovers {
    _$isFetchingDirCoversAtom.reportRead();
    return super.isFetchingDirCovers;
  }

  @override
  set isFetchingDirCovers(bool value) {
    _$isFetchingDirCoversAtom.reportWrite(value, super.isFetchingDirCovers, () {
      super.isFetchingDirCovers = value;
    });
  }

  late final _$dirCoverProgressAtom =
      Atom(name: '_LocalController.dirCoverProgress', context: context);

  @override
  String get dirCoverProgress {
    _$dirCoverProgressAtom.reportRead();
    return super.dirCoverProgress;
  }

  @override
  set dirCoverProgress(String value) {
    _$dirCoverProgressAtom.reportWrite(value, super.dirCoverProgress, () {
      super.dirCoverProgress = value;
    });
  }

  late final _$dirCoverCurrentAtom =
      Atom(name: '_LocalController.dirCoverCurrent', context: context);

  @override
  int get dirCoverCurrent {
    _$dirCoverCurrentAtom.reportRead();
    return super.dirCoverCurrent;
  }

  @override
  set dirCoverCurrent(int value) {
    _$dirCoverCurrentAtom.reportWrite(value, super.dirCoverCurrent, () {
      super.dirCoverCurrent = value;
    });
  }

  late final _$dirCoverTotalAtom =
      Atom(name: '_LocalController.dirCoverTotal', context: context);

  @override
  int get dirCoverTotal {
    _$dirCoverTotalAtom.reportRead();
    return super.dirCoverTotal;
  }

  @override
  set dirCoverTotal(int value) {
    _$dirCoverTotalAtom.reportWrite(value, super.dirCoverTotal, () {
      super.dirCoverTotal = value;
    });
  }

  late final _$initAsyncAction =
      AsyncAction('_LocalController.init', context: context);

  @override
  Future<void> init() {
    return _$initAsyncAction.run(() => super.init());
  }

  late final _$navigateToAsyncAction =
      AsyncAction('_LocalController.navigateTo', context: context);

  @override
  Future<void> navigateTo(String path) {
    return _$navigateToAsyncAction.run(() => super.navigateTo(path));
  }

  late final _$fetchPostersAsyncAction =
      AsyncAction('_LocalController.fetchPosters', context: context);

  @override
  Future<Map<String, int>> fetchPosters() {
    return _$fetchPostersAsyncAction.run(() => super.fetchPosters());
  }

  late final _$fetchPosterForItemAsyncAction =
      AsyncAction('_LocalController.fetchPosterForItem', context: context);

  @override
  Future<Map<String, int>> fetchPosterForItem(LocalFileItem item) {
    return _$fetchPosterForItemAsyncAction
        .run(() => super.fetchPosterForItem(item));
  }

  late final _$fetchPosterForItemsAsyncAction =
      AsyncAction('_LocalController.fetchPosterForItems', context: context);

  @override
  Future<Map<String, int>> fetchPosterForItems(
      List<LocalFileItem> targetItems) {
    return _$fetchPosterForItemsAsyncAction
        .run(() => super.fetchPosterForItems(targetItems));
  }

  late final _$fetchMediaInfoAsyncAction =
      AsyncAction('_LocalController.fetchMediaInfo', context: context);

  @override
  Future<int> fetchMediaInfo() {
    return _$fetchMediaInfoAsyncAction.run(() => super.fetchMediaInfo());
  }

  late final _$fetchThumbnailsAsyncAction =
      AsyncAction('_LocalController.fetchThumbnails', context: context);

  @override
  Future<int> fetchThumbnails() {
    return _$fetchThumbnailsAsyncAction.run(() => super.fetchThumbnails());
  }

  late final _$removeMediaSourceAsyncAction =
      AsyncAction('_LocalController.removeMediaSource', context: context);

  @override
  Future<bool> removeMediaSource(String path) {
    return _$removeMediaSourceAsyncAction
        .run(() => super.removeMediaSource(path));
  }

  late final _$removeUnavailableMediaSourcesAsyncAction = AsyncAction(
      '_LocalController.removeUnavailableMediaSources',
      context: context);

  @override
  Future<int> removeUnavailableMediaSources() {
    return _$removeUnavailableMediaSourcesAsyncAction
        .run(() => super.removeUnavailableMediaSources());
  }

  late final _$refreshLocalLibraryIndexAsyncAction = AsyncAction(
      '_LocalController.refreshLocalLibraryIndex',
      context: context);

  @override
  Future<Map<String, int>> refreshLocalLibraryIndex(
      {bool throwOnFailure = false}) {
    return _$refreshLocalLibraryIndexAsyncAction.run(
        () => super.refreshLocalLibraryIndex(throwOnFailure: throwOnFailure));
  }

  late final _$retryFailedLocalLibraryIndexItemsAsyncAction = AsyncAction(
      '_LocalController.retryFailedLocalLibraryIndexItems',
      context: context);

  @override
  Future<Map<String, int>> retryFailedLocalLibraryIndexItems() {
    return _$retryFailedLocalLibraryIndexItemsAsyncAction
        .run(() => super.retryFailedLocalLibraryIndexItems());
  }

  late final _$scrapeTmdbMetadataAsyncAction =
      AsyncAction('_LocalController.scrapeTmdbMetadata', context: context);

  @override
  Future<int> scrapeTmdbMetadata() {
    return _$scrapeTmdbMetadataAsyncAction
        .run(() => super.scrapeTmdbMetadata());
  }

  late final _$updateLocalLibraryItemAsyncAction =
      AsyncAction('_LocalController.updateLocalLibraryItem', context: context);

  @override
  Future<void> updateLocalLibraryItem(LocalMediaIndexItem item,
      {required String seriesName,
      int? seasonNumber,
      int? episodeNumber,
      String? episodeTitle,
      String? releaseGroup,
      String? resolution,
      String? source,
      String? codec}) {
    return _$updateLocalLibraryItemAsyncAction.run(() => super
        .updateLocalLibraryItem(item,
            seriesName: seriesName,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle,
            releaseGroup: releaseGroup,
            resolution: resolution,
            source: source,
            codec: codec));
  }

  late final _$updateLocalSeriesTitleAsyncAction =
      AsyncAction('_LocalController.updateLocalSeriesTitle', context: context);

  @override
  Future<bool> updateLocalSeriesTitle(
      Iterable<String> videoPaths, String title) {
    return _$updateLocalSeriesTitleAsyncAction
        .run(() => super.updateLocalSeriesTitle(videoPaths, title));
  }

  late final _$navigateUpAsyncAction =
      AsyncAction('_LocalController.navigateUp', context: context);

  @override
  Future<void> navigateUp() {
    return _$navigateUpAsyncAction.run(() => super.navigateUp());
  }

  late final _$refreshAsyncAction =
      AsyncAction('_LocalController.refresh', context: context);

  @override
  Future<void> refresh() {
    return _$refreshAsyncAction.run(() => super.refresh());
  }

  late final _$toggleSortAsyncAction =
      AsyncAction('_LocalController.toggleSort', context: context);

  @override
  Future<void> toggleSort(String field) {
    return _$toggleSortAsyncAction.run(() => super.toggleSort(field));
  }

  late final _$fetchDirectoryCoversAsyncAction =
      AsyncAction('_LocalController.fetchDirectoryCovers', context: context);

  @override
  Future<int> fetchDirectoryCovers() {
    return _$fetchDirectoryCoversAsyncAction
        .run(() => super.fetchDirectoryCovers());
  }

  late final _$_LocalControllerActionController =
      ActionController(name: '_LocalController', context: context);

  @override
  void reloadMediaSources() {
    final _$actionInfo = _$_LocalControllerActionController.startAction(
        name: '_LocalController.reloadMediaSources');
    try {
      return super.reloadMediaSources();
    } finally {
      _$_LocalControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void reloadLocalLibraryIndex() {
    final _$actionInfo = _$_LocalControllerActionController.startAction(
        name: '_LocalController.reloadLocalLibraryIndex');
    try {
      return super.reloadLocalLibraryIndex();
    } finally {
      _$_LocalControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void cancelLocalLibraryIndex() {
    final _$actionInfo = _$_LocalControllerActionController.startAction(
        name: '_LocalController.cancelLocalLibraryIndex');
    try {
      return super.cancelLocalLibraryIndex();
    } finally {
      _$_LocalControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
currentPath: ${currentPath},
items: ${items},
isLoading: ${isLoading},
errorMessage: ${errorMessage},
sortBy: ${sortBy},
sortAscending: ${sortAscending},
pathHistory: ${pathHistory},
mediaSources: ${mediaSources},
isFetchingPosters: ${isFetchingPosters},
posterProgress: ${posterProgress},
posterProgressValue: ${posterProgressValue},
posterCurrentFile: ${posterCurrentFile},
posterCurrent: ${posterCurrent},
posterTotal: ${posterTotal},
isFetchingMediaInfo: ${isFetchingMediaInfo},
mediaInfoCurrentFile: ${mediaInfoCurrentFile},
mediaInfoCurrent: ${mediaInfoCurrent},
mediaInfoTotal: ${mediaInfoTotal},
isFetchingThumbnails: ${isFetchingThumbnails},
thumbnailCurrentFile: ${thumbnailCurrentFile},
thumbnailCurrent: ${thumbnailCurrent},
thumbnailTotal: ${thumbnailTotal},
localLibraryItems: ${localLibraryItems},
isScrapingTmdb: ${isScrapingTmdb},
tmdbScrapeProgress: ${tmdbScrapeProgress},
tmdbScrapeCurrent: ${tmdbScrapeCurrent},
tmdbScrapeTotal: ${tmdbScrapeTotal},
isIndexingLibrary: ${isIndexingLibrary},
libraryIndexCurrentFile: ${libraryIndexCurrentFile},
libraryIndexCurrent: ${libraryIndexCurrent},
libraryIndexTotal: ${libraryIndexTotal},
libraryIndexProgressValue: ${libraryIndexProgressValue},
libraryIndexProgress: ${libraryIndexProgress},
libraryIndexSummary: ${libraryIndexSummary},
cancelLibraryIndexRequested: ${cancelLibraryIndexRequested},
libraryIndexFailures: ${libraryIndexFailures},
isFetchingDirCovers: ${isFetchingDirCovers},
dirCoverProgress: ${dirCoverProgress},
dirCoverCurrent: ${dirCoverCurrent},
dirCoverTotal: ${dirCoverTotal},
localLibraryVideoCount: ${localLibraryVideoCount},
mediaLibraryVideoCount: ${mediaLibraryVideoCount},
localLibrarySeriesCount: ${localLibrarySeriesCount},
localLibrarySeries: ${localLibrarySeries}
    ''';
  }
}
