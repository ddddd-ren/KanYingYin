import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/history/application/playback_history_repository.dart';
import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';

/// 为页面提供观看历史状态，并将高频播放进度合并后写入磁盘。
class PlaybackHistoryController extends ChangeNotifier {
  PlaybackHistoryController({PlaybackHistoryRepository? repository})
      : _repository = repository ?? PlaybackHistoryRepository();

  static const Duration persistInterval = Duration(seconds: 5);
  static const int minimumInitialPositionSeconds = 10;

  final PlaybackHistoryRepository _repository;
  final List<PlaybackHistoryEntry> _entries = <PlaybackHistoryEntry>[];
  Future<void> _loadFuture = Future<void>.value();
  Timer? _persistTimer;
  DateTime? _lastPersistAt;
  bool _loaded = false;
  bool _persistPending = false;
  Future<void> _operationQueue = Future<void>.value();

  List<PlaybackHistoryEntry> get entries =>
      List<PlaybackHistoryEntry>.unmodifiable(_entries);

  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    _loadFuture = _loadFuture.then((_) async {
      if (_loaded) return;
      try {
        _entries
          ..clear()
          ..addAll(await _repository.getAll());
        _backfillPosters();
      } on Object {
        // 历史存储不可用时不阻断媒体库和播放器启动。
        _entries.clear();
      } finally {
        _loaded = true;
        notifyListeners();
      }
    });
    return _loadFuture;
  }

  PlaybackHistoryEntry? find(String stableKey) {
    for (final entry in _entries) {
      if (entry.stableKey == stableKey) return entry;
    }
    return null;
  }

  Duration resumePosition(String stableKey) =>
      find(stableKey)?.resumePosition ?? Duration.zero;

  Future<void> record(
    PlaybackHistoryEntry entry, {
    bool forcePersist = false,
  }) =>
      _enqueue(() async {
        await ensureLoaded();
        final previousIndex =
            _entries.indexWhere((item) => item.stableKey == entry.stableKey);
        if (previousIndex < 0 &&
            entry.positionSeconds < minimumInitialPositionSeconds &&
            !entry.isCompleted) {
          return;
        }
        final nextEntry = _withPosterFallback(entry);
        _entries.removeWhere((item) => item.stableKey == entry.stableKey);
        _entries.insert(0, nextEntry);
        if (_entries.length > PlaybackHistoryRepository.maxEntries) {
          _entries.removeRange(
            PlaybackHistoryRepository.maxEntries,
            _entries.length,
          );
        }
        _persistPending = true;
        if (previousIndex != 0 || forcePersist) notifyListeners();
        if (forcePersist) {
          await _flushNow();
        } else {
          _schedulePersist();
        }
      });

  PlaybackHistoryEntry _withPosterFallback(PlaybackHistoryEntry entry) {
    final series = entry.seriesTitle.trim().toLowerCase();
    if (series.isEmpty) return entry;
    PlaybackHistoryEntry? fallback;
    for (final candidate in _entries) {
      if (candidate.sourceId == entry.sourceId &&
          candidate.seriesTitle.trim().toLowerCase() == series &&
          (_hasText(candidate.posterUrl) ||
              _hasText(candidate.posterCachePath))) {
        fallback = candidate;
        break;
      }
    }
    return entry.copyWith(
      posterUrl:
          _hasText(entry.posterUrl) ? entry.posterUrl : fallback?.posterUrl,
      posterCachePath: _hasText(entry.posterCachePath)
          ? entry.posterCachePath
          : fallback?.posterCachePath,
    );
  }

  void _backfillPosters() {
    // ponytail: 历史最多 100 条；超过上限再按剧集建立索引。
    for (var index = 0; index < _entries.length; index++) {
      _entries[index] = _withPosterFallback(_entries[index]);
    }
  }

  static bool _hasText(String? value) => value?.trim().isNotEmpty == true;

  Future<void> delete(String stableKey) => _enqueue(() async {
        await ensureLoaded();
        _entries.removeWhere((entry) => entry.stableKey == stableKey);
        _persistPending = true;
        notifyListeners();
        await _flushNow();
      });

  Future<void> clear() => _enqueue(() async {
        await ensureLoaded();
        _entries.clear();
        _persistPending = true;
        notifyListeners();
        await _flushNow();
      });

  Future<void> flush() => _enqueue(_flushNow);

  Future<void> _flushNow() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    if (!_persistPending) return;
    await ensureLoaded();
    await _repository.replaceAll(_entries);
    _persistPending = false;
    _lastPersistAt = DateTime.now();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _operationQueue.then((_) => operation());
    _operationQueue = next.catchError((Object error, StackTrace stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    });
    return next;
  }

  void _schedulePersist() {
    if (_persistTimer != null) return;
    final last = _lastPersistAt;
    final delay = last == null
        ? persistInterval
        : persistInterval - DateTime.now().difference(last);
    _persistTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(flush()),
    );
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    unawaited(flush());
    super.dispose();
  }
}
