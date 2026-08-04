import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/repositories/local_media_tag_repository.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory hiveDirectory;
  late Box<Object?> box;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('local_media_tags_');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<Object?>('settings');
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteFromDisk();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('标签按作品持久化、去重并过滤空值和超长值', () async {
    final repository = LocalMediaTagRepository(box: box);
    await repository.saveForSeries('  动画作品  ', <String>[
      ' 收藏 ',
      '收藏',
      '',
      '待看',
      'x' * 33,
    ]);

    expect(repository.getAll(), <String, List<String>>{
      '动画作品': <String>['收藏', '待看'],
    });
    expect(
      box.get(SettingBoxKey.localMediaLibraryTags),
      <String, List<String>>{
        '动画作品': <String>['收藏', '待看']
      },
    );
  });

  test('保存空标签会移除作品记录', () async {
    final repository = LocalMediaTagRepository(box: box);
    await repository.saveForSeries('作品', const <String>['收藏']);
    await repository.saveForSeries('作品', const <String>[]);

    expect(repository.getAll(), isEmpty);
  });
}
