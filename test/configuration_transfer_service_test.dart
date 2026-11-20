import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_transfer_service.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_user_data_store.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_user_data.dart';

void main() {
  test('导出捕获 TMDB 和全部来源凭据且 inspect 不写入目标配置', () async {
    final credentialStore = MemoryCloudCredentialStore();
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentialStore,
    );
    final tmdbManager = TmdbCredentialManager(
      store: MemoryTmdbCredentialStore(),
      legacyReader: () => '',
      legacyDelete: () async {},
      warningLogger: (_) {},
    );
    await tmdbManager.initialize();
    final userDataStore = _BackupStore();
    final importer = ConfigurationImporter(
      userDataStore: userDataStore,
      sourceRepository: sourceRepository,
      tmdbCredentialManager: tmdbManager,
    );
    final service = ConfigurationTransferService(
      userDataStore: userDataStore,
      sourceRepository: sourceRepository,
      tmdbCredentialManager: tmdbManager,
      importer: importer,
      codec: ConfigurationArchiveCodec(),
      now: () => DateTime.utc(2026, 8, 7),
      appVersion: '2.1.142',
    );
    final source = CloudSource(
      id: 'quark-fixture',
      type: CloudSourceType.quark,
      name: '夸克影视',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: const <String>['/影视'],
      scanStatus: CloudScanStatus.completed,
      lastScannedAt: DateTime.utc(2026, 8, 6),
      indexedVideoCount: 10,
    );
    await sourceRepository.save(source);
    await credentialStore.write(
      source.id,
      const CloudCredential(cookie: 'cookie-secret'),
    );
    await tmdbManager.save('tmdb-secret');

    final bytes = await service.exportEncrypted(password: 'export-pass');
    await sourceRepository.delete(source.id);
    await tmdbManager.save('target-key');
    userDataStore.value = PortableUserData.fromJson({});

    await expectLater(service.inspect(bytes, password: 'wrong-password'),
        throwsA(isA<ConfigurationArchiveAuthenticationException>()));
    await expectLater(
        service.inspect(Uint8List.fromList([1, 2, 3]), password: 'export-pass'),
        throwsA(isA<ConfigurationArchiveFormatException>()));
    expect(await sourceRepository.getAll(), isEmpty);
    expect(tmdbManager.read(), 'target-key');
    expect(userDataStore.writes, 0);

    final session = await service.inspect(bytes, password: 'export-pass');
    expect(session.summary.added, 1);
    expect(session.summary.tmdbWillUpdate, isTrue);
    expect(session.configuration.userData!.states['missing']!.favorite, isTrue);
    expect(
        session.configuration.userData!.bookmarks['local|missing.mp4']!.single
            .position,
        const Duration(seconds: 3));
    expect(session.configuration.cloudSources.single.source.scanStatus,
        CloudScanStatus.never);
    expect(await sourceRepository.getAll(), isEmpty);
    expect(tmdbManager.read(), 'target-key');

    final remapped = await service
        .remapSession(session, localRoots: {r'd:\media': r'e:\restored'});
    expect(userDataStore.writes, 0);
    final result = await service.apply(remapped);
    expect(result.added, 1);
    expect(tmdbManager.read(), 'tmdb-secret');
    expect((await credentialStore.read(source.id))?.cookie, 'cookie-secret');
    expect(userDataStore.value.bookmarks.keys,
        contains(r'local|e:\restored\movie.mkv'));
    expect(userDataStore.value.bookmarks.keys,
        isNot(contains(r'local|d:\media\movie.mkv')));
  });
}

class _BackupStore implements ConfigurationUserDataStore {
  int writes = 0;
  PortableUserData value = PortableUserData.fromJson({
    'localRoots': [r'd:\media'],
    'states': {
      'missing': {'favorite': true}
    },
    'bookmarks': {
      r'local|d:\media\movie.mkv': [
        {'positionMillis': 5000}
      ],
      'local|missing.mp4': [
        {'positionMillis': 3000}
      ]
    },
  });
  @override
  Future<PortableUserData> capture() async => value;
  @override
  Future<void> replace(PortableUserData data) async {
    writes++;
    value = data;
  }
}
