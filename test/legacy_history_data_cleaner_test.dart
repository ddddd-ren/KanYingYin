import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/legacy_history_data_cleaner.dart';

void main() {
  test('只删除旧历史文件且重复执行安全', () async {
    final directory =
        await Directory.systemTemp.createTemp('legacy_history_cleanup_');
    addTearDown(() => directory.delete(recursive: true));
    final history = File('${directory.path}/histories.hive');
    final lock = File('${directory.path}/histories.lock');
    final setting = File('${directory.path}/setting.hive');
    final media = File('${directory.path}/movie.mkv');
    await history.writeAsString('history');
    await lock.writeAsString('lock');
    await setting.writeAsString('setting');
    await media.writeAsString('video');

    await LegacyHistoryDataCleaner.deleteFrom(directory);
    await LegacyHistoryDataCleaner.deleteFrom(directory);

    expect(await history.exists(), isFalse);
    expect(await lock.exists(), isFalse);
    expect(await setting.exists(), isTrue);
    expect(await media.exists(), isTrue);
  });
}
