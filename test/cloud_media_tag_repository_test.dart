import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/repositories/cloud_media_tag_repository.dart';

void main() {
  test('网盘标签按来源和资源持久化并规范化', () async {
    final repository = CloudMediaTagRepository(
      storage: MemoryCloudMediaTagStorage(),
    );

    await repository.saveForResource('source-a', 'work-a', <String>[
      ' 收藏 ',
      '收藏',
      '',
      '待看',
      'x' * 33,
    ]);
    await repository.saveForResource(
      'source-b',
      'work-a',
      const <String>['另一来源'],
    );

    expect(
      await repository.getBySource('source-a'),
      <String, List<String>>{
        'work-a': <String>['收藏', '待看'],
      },
    );
    expect(
      await repository.getBySource('source-b'),
      <String, List<String>>{
        'work-a': <String>['另一来源'],
      },
    );
  });

  test('空标签删除资源记录且移除来源不会影响其他来源', () async {
    final storage = MemoryCloudMediaTagStorage();
    final repository = CloudMediaTagRepository(storage: storage);
    await repository
        .saveForResource('source-a', 'work-a', const <String>['收藏']);
    await repository
        .saveForResource('source-b', 'work-b', const <String>['待看']);

    await repository.saveForResource('source-a', 'work-a', const <String>[]);
    expect(await repository.getBySource('source-a'), isEmpty);

    await repository.removeSource('source-b');
    expect(await repository.getBySource('source-b'), isEmpty);
    expect(await storage.read(), isEmpty);
  });
}
