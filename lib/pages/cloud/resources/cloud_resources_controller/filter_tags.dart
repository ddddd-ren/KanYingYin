part of '../cloud_resources_controller.dart';

/// 过滤与集合派生：搜索关键字、流派、自定义标签与可见条目/集合视图。
mixin _CloudFilterTagsMixin on _CloudResourcesControllerBase {
  List<String> get availableGenres =>
      _genreFilter.availableGenres(_indexedItems.values);

  List<String> get availableCustomTags {
    final tags = <String>{};
    for (final item in _indexedItems.values) {
      tags.addAll(_customTagsForItem(item));
    }
    return tags.toList(growable: false)..sort();
  }

  List<String> get availableTags {
    final tags = <String>{
      ...availableGenres,
      ...availableCustomTags,
    };
    return tags.toList(growable: false)..sort();
  }

  List<CloudMediaIndexItem> get visibleIndexedItems {
    final scopeTree = _directoryScopeTree;
    return _genreFilter
        .apply(
          _indexedItems.values,
          _selectedGenres,
          customTagsFor: _customTagsForItem,
        )
        .where(
          (item) =>
              !_isHidden(
                sourceId: item.sourceId,
                remoteId: item.remoteId,
                remotePath: item.remotePath,
              ) &&
              scopeTree.contains(
                item.remotePath,
                currentDirectoryScope,
              ),
        )
        .toList(growable: false);
  }

  List<CloudFileEntry> get visibleEntries {
    final keyword = query.trim().toLowerCase();
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    final scopeTree = _directoryScopeTree;
    final filtered = entries
        .where(
          (entry) =>
              !_isHiddenEntry(entry) &&
              LocalVideoFileTypes.isRecognizedVideo(
                entry.name,
                size: entry.size,
                minSizeBytes: minSizeBytes,
              ) &&
              scopeTree.contains(
                entry.remotePath,
                currentDirectoryScope,
              ) &&
              (keyword.isEmpty || entry.name.toLowerCase().contains(keyword)),
        )
        .toList(growable: false);
    filtered.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );
    return filtered;
  }

  CloudResourceCollection get collection {
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    final cached = _collectionCache;
    if (cached != null && _collectionMinSizeBytes == minSizeBytes) {
      return cached;
    }
    _collectionCache = null;
    _collectionMinSizeBytes = minSizeBytes;
    final scopedItems = visibleIndexedItems;
    if (_workTmdbCoordinator != null && _works.isNotEmpty) {
      final visibleWorkKeys =
          scopedItems.map((item) => item.workKey).whereType<String>().toSet();
      return _collectionCache = _collectionGrouper.group(
        items: scopedItems,
        works: _works
            .where((work) => visibleWorkKeys.contains(work.workKey))
            .toList(growable: false),
        recordsByWorkKey: workTmdbRecords,
        query: query,
      );
    }
    final scopeTree = _directoryScopeTree;
    return _collectionCache = _collectionGrouper.group(
      sourceId: selectedSource?.id ?? '',
      entries: entries
          .where(
            (entry) =>
                !_isHiddenEntry(entry) &&
                _matchesSelectedGenres(entry) &&
                scopeTree.contains(
                  entry.remotePath,
                  currentDirectoryScope,
                ),
          )
          .toList(growable: false),
      records: tmdbRecords,
      minSizeBytes: minSizeBytes,
      query: query,
    );
  }

  List<CloudFileEntry> get tmdbEntriesForSelectedSource {
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    return entries
        .where(
          (entry) => LocalVideoFileTypes.isRecognizedVideo(
            entry.name,
            size: entry.size,
            minSizeBytes: minSizeBytes,
          ),
        )
        .toList(growable: false);
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    _invalidateCollection();
    _notify();
  }

  void toggleGenre(String genre) {
    final normalized = genre.trim();
    if (normalized.isEmpty || !availableTags.contains(normalized)) return;
    if (!_selectedGenres.remove(normalized)) {
      _selectedGenres.add(normalized);
    }
    _invalidateCollection();
    _notify();
  }

  void clearGenres() {
    if (_selectedGenres.isEmpty) return;
    _selectedGenres.clear();
    _invalidateCollection();
    _notify();
  }

  List<String> customTagsForGroup(CloudResourceMediaGroup group) {
    final key = _customTagKeyForGroup(group);
    return List<String>.unmodifiable(
      _customTagsByResourceKey[key] ?? const <String>[],
    );
  }

  Future<void> saveCustomTags(
    CloudResourceMediaGroup group,
    Iterable<String> tags,
  ) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final key = _customTagKeyForGroup(group);
    await _mediaTagRepository.saveForResource(source.id, key, tags);
    if (selectedSource?.id != source.id) return;
    final saved = await _mediaTagRepository.getBySource(source.id);
    _customTagsByResourceKey
      ..clear()
      ..addAll(saved);
    _reconcileSelectedGenres();
    _invalidateCollection();
    _notify();
  }

  bool _matchesSelectedGenres(CloudFileEntry entry) {
    if (_selectedGenres.isEmpty) return true;
    final item = _indexedItemFor(entry);
    if (item == null) return false;
    return _genreFilter.apply(
      <CloudMediaIndexItem>[item],
      _selectedGenres,
      customTagsFor: _customTagsForItem,
    ).isNotEmpty;
  }

  @override
  void _reconcileSelectedGenres() {
    final retained = _genreFilter.retainAvailable(
      _selectedGenres,
      availableTags,
    );
    if (setEquals(retained, _selectedGenres)) return;
    _selectedGenres
      ..clear()
      ..addAll(retained);
    _invalidateCollection();
  }

  Iterable<String> _customTagsForItem(CloudMediaIndexItem item) sync* {
    final tags = <String>{};
    for (final key in _customTagKeysForItem(item)) {
      tags.addAll(_customTagsByResourceKey[key] ?? const <String>[]);
    }
    yield* tags;
  }

  Iterable<String> _customTagKeysForItem(CloudMediaIndexItem item) sync* {
    final resourceKey = _resourceKeyForItem(item);
    yield resourceKey;
    final workKey = item.workKey?.trim();
    if (workKey != null && workKey.isNotEmpty) {
      yield workKey;
    }

    final record = tmdbRecords[resourceKey];
    final tmdbId = record?.status == CloudResourceTmdbStatus.matched
        ? record?.tmdbId
        : record == null
            ? item.tmdbId
            : null;
    final mediaType = record?.status == CloudResourceTmdbStatus.matched
        ? record?.mediaType
        : record == null
            ? _tmdbMediaTypeForItem(item)
            : null;
    if (tmdbId != null && mediaType != null) {
      yield '${item.sourceId}|tmdb|${mediaType.name}|$tmdbId';
    }

    final normalizedSeriesName =
        CloudSeriesIdentityResolver.normalizeSeriesName(item.seriesName);
    if (normalizedSeriesName.isNotEmpty && item.episodeNumber != null) {
      yield '${item.sourceId}|series|$normalizedSeriesName';
    }
  }

  TmdbMediaType? _tmdbMediaTypeForItem(CloudMediaIndexItem item) {
    return switch (item.mediaType) {
      CloudMediaType.movie => TmdbMediaType.movie,
      CloudMediaType.series ||
      CloudMediaType.episode ||
      CloudMediaType.special =>
        TmdbMediaType.tv,
      CloudMediaType.unknown => null,
    };
  }

  String _customTagKeyForGroup(CloudResourceMediaGroup group) {
    return group.isWorkScoped ? group.workKey : group.stableKey;
  }
}
