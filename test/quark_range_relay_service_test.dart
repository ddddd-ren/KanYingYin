import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_relay_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('只清理超过 24 小时且名称匹配的夸克中转目录', () async {
    final root = await Directory.systemTemp.createTemp('quark-relay-root-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final oldSession = await _sessionDirectory(
      root,
      'quark-relay-00000000000000000000000000000000',
      DateTime.utc(2026, 7, 19),
    );
    final recentSession = await _sessionDirectory(
      root,
      'quark-relay-11111111111111111111111111111111',
      DateTime.utc(2026, 7, 20, 18),
    );
    final unrelated = await _sessionDirectory(
      root,
      'other-cache',
      DateTime.utc(2026, 7, 19),
    );

    await QuarkRangeRelayService.cleanupOrphans(
      root,
      now: DateTime.utc(2026, 7, 21),
    );

    expect(await oldSession.exists(), isFalse);
    expect(await recentSession.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });
}

Future<Directory> _sessionDirectory(
  Directory root,
  String name,
  DateTime createdAt,
) async {
  final directory = await Directory(p.join(root.path, name)).create();
  final marker = File(p.join(directory.path, '.created'));
  await marker.writeAsBytes(const <int>[]);
  await marker.setLastModified(createdAt);
  return directory;
}
