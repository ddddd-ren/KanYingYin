import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';

void main() {
  test('TMDB Key 缺失时只读缓存不发请求', () async {
    final fixture = _Fixture(apiKey: '');
    final matched = CloudResourceTmdbRecord.unmatched(
      sourceId: 'source-a',
      remoteId: 'folder-a',
      remotePath: '/影视/A',
      displayName: 'A',
      resourceKind: CloudResourceKind.directory,
      checkedAt: DateTime.utc(2026, 7, 18),
    );
    await fixture.repository.upsert(matched);

    await fixture.coordinator.loadAndSchedule(
      _context(<CloudFileEntry>[_directory('folder-a', '/影视/A', 'A')]),
    );

    expect(fixture.client.searchCalls, 0);
    expect(fixture.coordinator.records[matched.stableKey], matched);
  });

  test('未匹配七天内不重试且失败可立即重试', () async {
    final fixture = _Fixture(apiKey: 'key');
    final recent = CloudResourceTmdbRecord.unmatched(
      sourceId: 'source-a',
      remoteId: 'recent',
      remotePath: '/影视/Recent',
      displayName: 'Recent',
      resourceKind: CloudResourceKind.directory,
      checkedAt: DateTime.utc(2026, 7, 18),
    );
    final failed = CloudResourceTmdbRecord.failed(
      sourceId: 'source-a',
      remoteId: 'failed',
      remotePath: '/影视/Failed',
      displayName: 'Failed',
      resourceKind: CloudResourceKind.directory,
      checkedAt: DateTime.utc(2026, 7, 19),
    );
    await fixture.repository.upsert(recent);
    await fixture.repository.upsert(failed);

    await fixture.coordinator.loadAndSchedule(
      _context(<CloudFileEntry>[
        _directory('recent', '/影视/Recent', 'Recent'),
        _directory('failed', '/影视/Failed', 'Failed'),
      ]),
    );

    expect(fixture.client.queries, contains('Failed'));
    expect(fixture.client.queries, isNot(contains('Recent')));
  });

  test('自动请求并发不超过二且媒体根目录包含独立视频', () async {
    final fixture = _Fixture(
      apiKey: 'key',
      client: _FakeTmdbClient(delay: const Duration(milliseconds: 20)),
    );

    await fixture.coordinator.loadAndSchedule(
      _context(<CloudFileEntry>[
        _directory('a', '/影视/A', 'A'),
        _directory('b', '/影视/B', 'B'),
        _directory('c', '/影视/C', 'C'),
        _video('d', '/影视/D.mkv', 'D.mkv'),
      ]),
    );

    expect(fixture.client.maximumConcurrentCalls, 2);
    expect(fixture.client.queries, containsAll(<String>['A', 'B', 'C', 'D']));
    expect(fixture.coordinator.scrapingKeys, isEmpty);
  });

  test('子目录只调度文件夹而不重复刮削单集', () async {
    final fixture = _Fixture(apiKey: 'key');

    await fixture.coordinator.loadAndSchedule(
      _context(
        <CloudFileEntry>[
          _directory('season', '/影视/剧集/Season 1', 'Season 1'),
          _video('episode', '/影视/剧集/E01.mkv', 'E01.mkv'),
        ],
        isConfiguredRoot: false,
      ),
    );

    expect(fixture.client.queries, contains('Season 1'));
    expect(fixture.client.queries, isNot(contains('E01')));
  });

  test('没有 TMDB Key 也能保存和恢复自定义剧名', () async {
    final fixture = _Fixture(apiKey: '');
    final target = _target();

    await fixture.coordinator.saveCustomTitle(target, '  新剧名  ');
    expect(
      fixture.coordinator.records[target.stableKey]?.effectiveTitle,
      '新剧名',
    );
    expect(fixture.client.searchCalls, 0);

    await fixture.coordinator.clearCustomTitle(target);
    expect(
      fixture.coordinator.records[target.stableKey]?.customTitle,
      isNull,
    );
    expect(fixture.client.searchCalls, 0);
  });

  test('失败状态更新不丢失自定义剧名', () async {
    final fixture = _Fixture(
      apiKey: 'key',
      client: _FakeTmdbClient(throwOnSearch: true),
    );
    final target = _target();
    await fixture.coordinator.saveCustomTitle(target, '新剧名');

    await fixture.coordinator.loadAndSchedule(
      _context(<CloudFileEntry>[
        _directory('folder-a', '/影视/A', 'A'),
      ]),
    );

    final stored = await fixture.repository.get(target.stableKey);
    expect(stored?.status, CloudResourceTmdbStatus.failed);
    expect(stored?.customTitle, '新剧名');
  });
}

CloudResourceTmdbTarget _target() => const CloudResourceTmdbTarget(
      sourceId: 'source-a',
      remote: CloudRemoteRef(id: 'folder-a', path: '/影视/A'),
      displayName: 'A',
      resourceKind: CloudResourceKind.directory,
    );

CloudResourceDirectoryContext _context(
  List<CloudFileEntry> entries, {
  bool isConfiguredRoot = true,
}) {
  return CloudResourceDirectoryContext(
    source: const CloudSource(
      id: 'source-a',
      type: CloudSourceType.quark,
      name: '夸克',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/影视'],
      rootRefs: <CloudRemoteRef>[
        CloudRemoteRef(id: 'root', path: '/影视'),
      ],
    ),
    directory: const CloudRemoteRef(id: 'root', path: '/影视'),
    entries: entries,
    isConfiguredRoot: isConfiguredRoot,
  );
}

CloudFileEntry _directory(String id, String path, String name) {
  return CloudFileEntry(
    id: id,
    remotePath: path,
    name: name,
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
}

CloudFileEntry _video(String id, String path, String name) {
  return CloudFileEntry(
    id: id,
    remotePath: path,
    name: name,
    size: 100,
    modifiedAt: null,
    isDirectory: false,
  );
}

class _Fixture {
  _Fixture({required String apiKey, _FakeTmdbClient? client})
      : client = client ?? _FakeTmdbClient(),
        repository = CloudResourceTmdbRepository(
          storage: MemoryCloudResourceTmdbStorage(),
        ) {
    coordinator = CloudResourceTmdbCoordinator(
      repository: repository,
      serviceFactory: (_) => CloudResourceTmdbService(
        repository: repository,
        indexRepository: CloudMediaIndexRepository(
          storage: MemoryCloudMediaIndexStorage(),
        ),
        client: this.client,
        now: () => DateTime.utc(2026, 7, 19),
      ),
      apiKeyProvider: () => apiKey,
      now: () => DateTime.utc(2026, 7, 19),
    );
  }

  final _FakeTmdbClient client;
  final CloudResourceTmdbRepository repository;
  late final CloudResourceTmdbCoordinator coordinator;
}

class _FakeTmdbClient implements ITmdbClient {
  _FakeTmdbClient({
    this.delay = Duration.zero,
    this.throwOnSearch = false,
  });

  final Duration delay;
  final bool throwOnSearch;
  final List<String> queries = <String>[];
  var searchCalls = 0;
  var concurrentCalls = 0;
  var maximumConcurrentCalls = 0;

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    searchCalls++;
    queries.add(query);
    concurrentCalls++;
    maximumConcurrentCalls = maximumConcurrentCalls < concurrentCalls
        ? concurrentCalls
        : maximumConcurrentCalls;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (throwOnSearch) throw StateError('模拟 TMDB 失败');
      return const <TmdbMetadata>[];
    } finally {
      concurrentCalls--;
    }
  }
}
