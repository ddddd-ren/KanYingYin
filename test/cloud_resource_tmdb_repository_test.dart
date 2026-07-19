import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';

void main() {
  test('并发更新不丢记录且按来源删除', () async {
    final repository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final first = _record('source-a', 'folder-a', '/A');
    final second = _record('source-a', 'folder-b', '/B');
    final retained = _record('source-b', 'folder-c', '/C');

    await Future.wait(<Future<void>>[
      repository.upsert(first),
      repository.upsert(second),
      repository.upsert(retained),
    ]);

    expect(await repository.getBySource('source-a'), hasLength(2));
    expect(await repository.get(first.stableKey), first);
    await repository.removeSource('source-a');
    expect(await repository.getBySource('source-a'), isEmpty);
    expect(await repository.getBySource('source-b'), <CloudResourceTmdbRecord>[
      retained,
    ]);
  });

  test('更新相同稳定键时替换旧记录', () async {
    final repository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final original = _record('source-a', 'folder-a', '/A');
    final updated = CloudResourceTmdbRecord.unmatched(
      sourceId: original.sourceId,
      remoteId: original.remoteId,
      remotePath: original.remotePath,
      displayName: '新名称',
      resourceKind: original.resourceKind,
      checkedAt: DateTime.utc(2026, 7, 20),
    );
    await repository.upsert(original);
    await repository.upsert(updated);

    expect(await repository.getBySource('source-a'), <CloudResourceTmdbRecord>[
      updated,
    ]);
  });
}

CloudResourceTmdbRecord _record(
  String sourceId,
  String remoteId,
  String remotePath,
) =>
    CloudResourceTmdbRecord.unmatched(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      displayName: remotePath,
      resourceKind: CloudResourceKind.directory,
      checkedAt: DateTime.utc(2026, 7, 19),
    );
