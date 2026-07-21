import 'dart:io';

import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';

typedef CloudRangeChunkLoader = Future<void> Function(
  ByteRange range,
  File destination,
);

class CloudChunkLoadException implements Exception {
  const CloudChunkLoadException(this.message);

  final String message;

  @override
  String toString() => 'CloudChunkLoadException($message)';
}

class CloudRangeChunkCache {
  CloudRangeChunkCache({
    required this.directory,
    required this.totalLength,
    this.chunkSize = 16 * 1024 * 1024,
    this.maxChunks = 16,
  })  : assert(totalLength > 0),
        assert(chunkSize > 0),
        assert(maxChunks > 0);

  final Directory directory;
  final int totalLength;
  final int chunkSize;
  final int maxChunks;

  final Map<int, _ChunkEntry> _entries = <int, _ChunkEntry>{};
  final Map<int, Future<_ChunkEntry>> _inFlight = <int, Future<_ChunkEntry>>{};
  var _accessTick = 0;
  var _closed = false;
  Future<void>? _closeFuture;

  int get cachedBytes => _entries.values.fold<int>(
        0,
        (total, entry) => total + entry.range.length,
      );

  List<int> get cachedChunkIndices {
    final indices = _entries.keys.toList()..sort();
    return List<int>.unmodifiable(indices);
  }

  Future<CloudRangeChunkHandle> acquire(
    int byteOffset,
    CloudRangeChunkLoader loader,
  ) async {
    if (_closed) throw StateError('分段缓存已关闭');
    if (byteOffset < 0 || byteOffset >= totalLength) {
      throw RangeError.range(byteOffset, 0, totalLength - 1, 'byteOffset');
    }

    final chunkIndex = byteOffset ~/ chunkSize;
    final cached = _entries[chunkIndex];
    if (cached != null) return _pin(cached);

    final loading = _inFlight[chunkIndex];
    if (loading != null) return _pin(await loading);

    final future = _makeRoomAndLoad(chunkIndex, loader);
    _inFlight[chunkIndex] = future;
    try {
      return _pin(await future);
    } finally {
      _inFlight.remove(chunkIndex);
    }
  }

  Future<_ChunkEntry> _makeRoomAndLoad(
    int chunkIndex,
    CloudRangeChunkLoader loader,
  ) async {
    await _makeRoomForChunk(chunkIndex);
    if (_closed) throw StateError('分段缓存已关闭');
    return _loadChunk(chunkIndex, loader);
  }

  CloudRangeChunkHandle _pin(_ChunkEntry entry) {
    if (_closed) throw StateError('分段缓存已关闭');
    entry.references++;
    entry.lastAccess = ++_accessTick;
    return CloudRangeChunkHandle._(this, entry);
  }

  Future<_ChunkEntry> _loadChunk(
    int chunkIndex,
    CloudRangeChunkLoader loader,
  ) async {
    await directory.create(recursive: true);
    final start = chunkIndex * chunkSize;
    final endInclusive = start + chunkSize - 1 < totalLength
        ? start + chunkSize - 1
        : totalLength - 1;
    final range = ByteRange(start, endInclusive);
    final part = File(
      '${directory.path}${Platform.pathSeparator}'
      'chunk-${chunkIndex.toString().padLeft(8, '0')}.part',
    );
    final completed = File(
      '${directory.path}${Platform.pathSeparator}'
      'chunk-${chunkIndex.toString().padLeft(8, '0')}.bin',
    );

    try {
      if (await part.exists()) await part.delete();
      await loader(range, part);
      if (_closed) throw StateError('分段缓存已关闭');
      final actualLength = await part.length();
      if (actualLength != range.length) {
        throw CloudChunkLoadException(
          '分段长度不符：期望 ${range.length}，实际 $actualLength',
        );
      }
      final file = await part.rename(completed.path);
      final entry = _ChunkEntry(
        chunkIndex: chunkIndex,
        range: range,
        file: file,
        lastAccess: ++_accessTick,
      );
      _entries[chunkIndex] = entry;
      return entry;
    } on CloudChunkLoadException {
      if (await part.exists()) await part.delete();
      rethrow;
    } on Object {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  Future<void> _makeRoomForChunk(int requestedChunkIndex) async {
    int otherLoads() => _inFlight.keys
        .where((chunkIndex) => chunkIndex != requestedChunkIndex)
        .length;

    // 无论当前 Future 是否已经注册，只统计其他正在加载的分段。
    while (_entries.length + otherLoads() >= maxChunks) {
      final candidates = _entries.values
          .where((entry) => entry.references == 0)
          .toList()
        ..sort(
            (first, second) => first.lastAccess.compareTo(second.lastAccess));
      if (candidates.isEmpty) {
        throw const CloudChunkLoadException('分段缓存容量已被正在使用的内容占满');
      }
      final victim = candidates.first;
      _entries.remove(victim.chunkIndex);
      if (await victim.file.exists()) await victim.file.delete();
    }
  }

  Future<void> _release(_ChunkEntry entry) async {
    if (entry.references > 0) entry.references--;
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final loading in _inFlight.values.toList()) {
      try {
        await loading;
      } on Object {
        // 加载失败不应阻断会话目录清理。
      }
    }
    _inFlight.clear();
    _entries.clear();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class CloudRangeChunkHandle {
  CloudRangeChunkHandle._(this._cache, this._entry);

  final CloudRangeChunkCache _cache;
  final _ChunkEntry _entry;
  var _released = false;

  ByteRange get range => _entry.range;
  File get file => _entry.file;

  Stream<List<int>> openRead({
    required int start,
    required int endInclusive,
  }) {
    if (_released) throw StateError('分段句柄已释放');
    if (start < range.start || endInclusive > range.endInclusive) {
      throw RangeError('读取范围不在当前分段内');
    }
    if (endInclusive < start) throw RangeError('读取结束位置早于开始位置');
    return file.openRead(
      start - range.start,
      endInclusive - range.start + 1,
    );
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _cache._release(_entry);
  }
}

class _ChunkEntry {
  _ChunkEntry({
    required this.chunkIndex,
    required this.range,
    required this.file,
    required this.lastAccess,
  });

  final int chunkIndex;
  final ByteRange range;
  final File file;
  int lastAccess;
  int references = 0;
}
