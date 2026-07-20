import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_chunk_cache.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';

void main() {
  late Directory directory;
  late CloudRangeChunkCache cache;
  var loadCalls = 0;

  Future<void> loader(ByteRange range, File destination) async {
    loadCalls++;
    await destination.writeAsBytes(
      <int>[
        for (var value = range.start; value <= range.endInclusive; value++)
          value,
      ],
      flush: true,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cloud-cache-test-');
    cache = CloudRangeChunkCache(
      directory: directory,
      totalLength: 10,
      chunkSize: 4,
      maxChunks: 2,
    );
    loadCalls = 0;
  });

  tearDown(() async {
    await cache.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('按分段边界加载且最后一段使用真实长度', () async {
    final first = await cache.acquire(1, loader);
    final last = await cache.acquire(9, loader);

    expect(first.range, const ByteRange(0, 3));
    expect(await _read(first, 1, 3), <int>[1, 2, 3]);
    expect(last.range, const ByteRange(8, 9));
    expect(await _read(last, 8, 9), <int>[8, 9]);
    expect(cache.cachedBytes, 6);

    await first.release();
    await last.release();
  });

  test('同一分段并发获取只执行一次加载', () async {
    final handles = await Future.wait(<Future<CloudRangeChunkHandle>>[
      cache.acquire(1, loader),
      cache.acquire(3, loader),
    ]);

    expect(loadCalls, 1);
    expect(handles[0].file.path, handles[1].file.path);
    await handles[0].release();
    await handles[1].release();
  });

  test('最近最少使用淘汰空闲分段', () async {
    final first = await cache.acquire(0, loader);
    await first.release();
    final second = await cache.acquire(4, loader);
    await second.release();

    final touched = await cache.acquire(0, loader);
    await touched.release();
    final third = await cache.acquire(8, loader);
    await third.release();

    expect(cache.cachedChunkIndices, <int>[0, 2]);
    expect(loadCalls, 3);
  });

  test('正在使用的分段不会被淘汰', () async {
    final pinned = await cache.acquire(0, loader);
    final second = await cache.acquire(4, loader);
    await second.release();
    final third = await cache.acquire(8, loader);
    await third.release();

    expect(cache.cachedChunkIndices, contains(0));
    expect(cache.cachedChunkIndices, isNot(contains(1)));
    await pinned.release();
  });

  test('加载长度不符时删除半成品且不写入缓存', () async {
    Future<void> shortLoader(ByteRange range, File destination) =>
        destination.writeAsBytes(<int>[range.start]);

    await expectLater(
      cache.acquire(0, shortLoader),
      throwsA(isA<CloudChunkLoadException>()),
    );
    expect(cache.cachedChunkIndices, isEmpty);
    expect(directory.listSync(), isEmpty);
  });

  test('关闭幂等并删除当前会话目录', () async {
    final handle = await cache.acquire(0, loader);
    await handle.release();

    await cache.close();
    await cache.close();

    expect(await directory.exists(), isFalse);
    await expectLater(
      cache.acquire(0, loader),
      throwsA(isA<StateError>()),
    );
  });
}

Future<List<int>> _read(
  CloudRangeChunkHandle handle,
  int start,
  int endInclusive,
) =>
    handle
        .openRead(start: start, endInclusive: endInclusive)
        .fold(<int>[], (bytes, chunk) => bytes..addAll(chunk));
