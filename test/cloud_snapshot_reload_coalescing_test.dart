import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

void main() {
  for (final queueLatest in [false, true]) {
    test('旧快照读取失败，待办刷新=$queueLatest 时保留正确结果', () async {
      final credentials = MemoryCloudCredentialStore();
      final sources = _FailOnceSources(credentials);
      await sources.save(const CloudSource(
        id: 'latest',
        type: CloudSourceType.openList,
        name: '最新来源',
        baseUrl: 'https://example.com',
        rootPaths: ['/影视'],
      ));
      sources.failNextRead = true;
      final controller = CloudResourcesController(
        repository: sources,
        credentialStore: credentials,
        mediaIndexRepository: CloudMediaIndexRepository(
          storage: MemoryCloudMediaIndexStorage(),
        ),
      );
      addTearDown(controller.dispose);
      final pending = controller.reloadMediaLibrarySnapshot();
      await sources.started.future;
      final check = expectLater(
        pending,
        queueLatest ? completes : throwsStateError,
      );
      if (queueLatest) {
        expect(identical(pending,
            controller.reloadMediaLibrarySnapshot(force: true)), isTrue);
      }
      sources.release.complete();
      await check;
      expect(sources.reads, queueLatest ? 2 : 1);
      if (queueLatest) {
        expect(controller.mediaLibrarySnapshot.filters.map((item) => item.id),
            contains('latest'));
      }
    });
  }

  test('连续强制刷新合并为最后一次，过期快照不继续遍历其他来源', () async {
    final credentials = MemoryCloudCredentialStore();
    final sources = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    for (final id in ['a', 'b']) {
      await sources.save(CloudSource(
        id: id,
        type: CloudSourceType.openList,
        name: id,
        baseUrl: 'https://example.com',
        rootPaths: const ['/影视'],
      ));
    }
    final index = _BlockedIndexRepository();
    final controller = CloudResourcesController(
      repository: sources,
      credentialStore: credentials,
      mediaIndexRepository: index,
    );
    addTearDown(controller.dispose);
    final pending = [controller.reloadMediaLibrarySnapshot()];
    await index.started.future;
    for (var i = 0; i < 20; i++) {
      pending.add(controller.reloadMediaLibrarySnapshot(force: true));
    }
    await Future<void>.delayed(Duration.zero);
    expect(index.reads, 1);
    index.release.complete();
    await Future.wait(pending);
    expect(index.reads, 3);
    expect(controller.mediaLibrarySnapshot.filters.map((item) => item.id),
        containsAll(['a', 'b']));
  });
}

class _FailOnceSources extends CloudSourceRepository {
  _FailOnceSources(CloudCredentialStore credentials)
      : super(storage: MemoryCloudSourceStorage(), credentialStore: credentials);

  final started = Completer<void>();
  final release = Completer<void>();
  int reads = 0;
  bool failNextRead = false;

  @override
  Future<List<CloudSource>> getAll() async {
    if (failNextRead) {
      failNextRead = false;
      reads++;
      started.complete();
      await release.future;
      throw StateError('短暂读取失败');
    }
    if (started.isCompleted) reads++;
    return super.getAll();
  }
}

class _BlockedIndexRepository extends CloudMediaIndexRepository {
  _BlockedIndexRepository() : super(storage: MemoryCloudMediaIndexStorage());

  final started = Completer<void>();
  final release = Completer<void>();
  int reads = 0;

  @override
  Future<CloudMediaIndexSnapshot> snapshot(String sourceId) async {
    reads++;
    if (reads == 1) {
      started.complete();
      await release.future;
    }
    return const CloudMediaIndexSnapshot(
      items: [],
      fingerprints: {},
      directoryEntries: <String, List<CloudFileEntry>>{},
      indexedRoots: [],
    );
  }
}
