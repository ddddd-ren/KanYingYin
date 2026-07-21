import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

void main() {
  test('安全存储值优先并清理旧值', () async {
    final store = MemoryTmdbCredentialStore(' secure-key ');
    var legacy = 'legacy-key';
    final manager = TmdbCredentialManager(
      store: store,
      legacyReader: () => legacy,
      legacyDelete: () async => legacy = '',
      warningLogger: (_) {},
    );

    await manager.initialize();

    expect(manager.read(), 'secure-key');
    expect(legacy, isEmpty);
  });

  test('旧值写入安全存储成功后才删除', () async {
    final store = MemoryTmdbCredentialStore();
    var legacy = ' legacy-key ';
    final manager = TmdbCredentialManager(
      store: store,
      legacyReader: () => legacy,
      legacyDelete: () async => legacy = '',
      warningLogger: (_) {},
    );

    await manager.initialize();

    expect(manager.read(), 'legacy-key');
    expect(await store.read(), 'legacy-key');
    expect(legacy, isEmpty);
  });

  test('安全存储写入失败时继续使用且保留旧值', () async {
    final store = _FailingTmdbCredentialStore(writeFails: true);
    var legacy = 'legacy-key';
    final manager = TmdbCredentialManager(
      store: store,
      legacyReader: () => legacy,
      legacyDelete: () async => legacy = '',
      warningLogger: (_) {},
    );

    await manager.initialize();

    expect(manager.read(), 'legacy-key');
    expect(legacy, 'legacy-key');
  });

  test('保存和清空用户凭据同步清理旧值', () async {
    final store = MemoryTmdbCredentialStore();
    var legacy = 'legacy-key';
    final manager = TmdbCredentialManager(
      store: store,
      legacyReader: () => legacy,
      legacyDelete: () async => legacy = '',
      warningLogger: (_) {},
    );
    await manager.initialize();

    await manager.save(' new-key ');
    expect(manager.read(), 'new-key');
    expect(await store.read(), 'new-key');
    expect(legacy, isEmpty);

    await manager.save('  ');
    expect(manager.read(), isEmpty);
    expect(await store.read(), isNull);
  });
}

class _FailingTmdbCredentialStore implements TmdbCredentialStore {
  _FailingTmdbCredentialStore({this.writeFails = false});

  final bool writeFails;

  @override
  Future<void> delete() async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {
    if (writeFails) throw const FileSystemException('安全存储不可用');
  }
}
