import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_transfer_service.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

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
    final importer = ConfigurationImporter(
      sourceRepository: sourceRepository,
      tmdbCredentialManager: tmdbManager,
    );
    final service = ConfigurationTransferService(
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

    final session = await service.inspect(bytes, password: 'export-pass');
    expect(session.summary.added, 1);
    expect(session.summary.tmdbWillUpdate, isTrue);
    expect(session.configuration.cloudSources.single.source.scanStatus,
        CloudScanStatus.never);
    expect(await sourceRepository.getAll(), isEmpty);
    expect(tmdbManager.read(), 'target-key');

    final result = await service.apply(session);
    expect(result.added, 1);
    expect(tmdbManager.read(), 'tmdb-secret');
    expect((await credentialStore.read(source.id))?.cookie, 'cookie-secret');
  });
}
