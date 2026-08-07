import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/features/tv_pairing/application/tv_pairing_controller.dart';
import 'package:kanyingyin/features/tv_pairing/application/tv_pairing_file_import_coordinator.dart';
import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_http_server.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryCloudCredentialStore credentialStore;
  late CloudSourceRepository repository;
  late TmdbCredentialManager tmdbManager;
  late _FakePairingServer server;
  late TvPairingController controller;

  setUp(() async {
    credentialStore = MemoryCloudCredentialStore();
    repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentialStore,
    );
    tmdbManager = TmdbCredentialManager(
      store: MemoryTmdbCredentialStore('old-tmdb-key'),
      legacyReader: () => '',
      legacyDelete: () async {},
      warningLogger: (_) {},
    );
    await tmdbManager.initialize();
    server = _FakePairingServer();
    controller = TvPairingController(
      importer: ConfigurationImporter(
        sourceRepository: repository,
        tmdbCredentialManager: tmdbManager,
      ),
      server: server,
      now: () => DateTime.utc(2026, 8, 6, 12),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('启动后公布配对地址且控制器字符串不包含令牌', () async {
    await controller.start();

    expect(controller.state, TvPairingState.active);
    expect(controller.endpoint?.host, '192.168.1.20');
    expect(controller.remaining, const Duration(minutes: 5));
    expect(controller.toString(), isNot(contains(server.session?.token ?? '')));
  });

  test('手机打开页面后进入 phoneConnected 且重复通知幂等', () async {
    await controller.start();

    server.notifyPhoneConnected();
    server.notifyPhoneConnected();

    expect(controller.state, TvPairingState.phoneConnected);
  });

  test('手机提交后预览并在 TV 确认后调用公共导入器', () async {
    await controller.start();
    server.notifyPhoneConnected();
    final submission = server.submit(_payload());
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, TvPairingState.awaitingConfirmation);
    expect(controller.pendingSummary?.cloudSourceCount, 1);
    expect(controller.pendingSummary?.requiresRootSelection, 0);
    expect(controller.pendingSummary.toString(),
        isNot(contains('secret-password')));
    expect(controller.pendingSummary.toString(),
        isNot(contains('secret-tmdb-key')));

    await controller.confirmPending();

    expect(await submission, TvPairingSubmissionResult.accepted);
    expect(controller.state, TvPairingState.success);
    expect(controller.completedSummary?.added, 1);
    expect(tmdbManager.exportForPairing(), 'secret-tmdb-key');
    expect((await repository.getById('cloud-1'))?.name, '家庭网盘');
    expect(
      (await credentialStore.read('cloud-1'))?.password,
      'secret-password',
    );
  });

  test('TV 拒绝后不写入配置且保持手机已连接状态', () async {
    await controller.start();
    server.notifyPhoneConnected();
    final submission = server.submit(_payload());
    await Future<void>.delayed(Duration.zero);

    controller.rejectPending();

    expect(await submission, TvPairingSubmissionResult.rejected);
    expect(controller.state, TvPairingState.phoneConnected);
    expect(tmdbManager.exportForPairing(), 'old-tmdb-key');
    expect(await repository.getAll(), isEmpty);
    expect(server.session?.isConsumed, isFalse);
  });

  test('公共导入器失败时返回 applyFailed 而不是用户拒绝', () async {
    controller.dispose();
    controller = TvPairingController(
      importer: const _FailingConfigurationImporter(),
      server: server,
      now: () => DateTime.utc(2026, 8, 6, 12),
    );
    await controller.start();
    final submission = server.submit(_payload());
    await Future<void>.delayed(Duration.zero);

    await controller.confirmPending();

    expect(await submission, TvPairingSubmissionResult.applyFailed);
    expect(controller.state, TvPairingState.error);
    expect(controller.errorMessage, '配置写入失败，原配置已保留');
    expect(server.session?.isConsumed, isFalse);
  });

  test('应用进入后台时停止监听并清除待确认配置', () async {
    await controller.start();
    final submission = server.submit(_payload());
    await Future<void>.delayed(Duration.zero);

    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);

    expect(await submission, TvPairingSubmissionResult.rejected);
    expect(server.stopCount, 1);
    expect(controller.state, TvPairingState.idle);
    expect(controller.pendingSummary, isNull);
  });

  test('配对确认会导入手机上传的配置和刮削资料文件', () async {
    controller.dispose();
    final fileImporter = _FakeTvPairingFileImporter();
    controller = TvPairingController(
      importer: ConfigurationImporter(
        sourceRepository: repository,
        tmdbCredentialManager: tmdbManager,
      ),
      fileImporter: fileImporter,
      server: server,
      now: () => DateTime.utc(2026, 8, 6, 12),
    );
    await controller.start();
    final submission = server.submit(_payloadWithFiles());
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, TvPairingState.awaitingConfirmation);
    expect(controller.pendingSummary?.hasConfigurationFile, isTrue);
    expect(controller.pendingSummary?.hasScrapedMetadataFile, isTrue);
    await controller.confirmPending();

    expect(await submission, TvPairingSubmissionResult.accepted);
    expect(fileImporter.previewCount, 1);
    expect(fileImporter.applyCount, 1);
    expect(controller.state, TvPairingState.success);
  });
}

TvPairingPayload _payload() => TvPairingPayload(
      protocolVersion: TvPairingPayload.currentProtocolVersion,
      deviceName: '客厅电视',
      configuration: PortableAppConfiguration.create(
        exportedAt: DateTime.utc(2026, 8, 7),
        appVersion: 'phone-web',
        tmdbApiKey: 'secret-tmdb-key',
        cloudSources: <PortableCloudSourceConfiguration>[
          PortableCloudSourceConfiguration.fromSource(
            source: const CloudSource(
              id: 'cloud-1',
              type: CloudSourceType.openList,
              name: '家庭网盘',
              baseUrl: 'https://cloud.example.com',
              rootPaths: <String>['/电影'],
            ),
            credential: const CloudCredential(password: 'secret-password'),
          ),
        ],
      ),
    );

TvPairingPayload _payloadWithFiles() => TvPairingPayload(
      protocolVersion: TvPairingPayload.currentProtocolVersion,
      deviceName: '客厅电视',
      configuration: PortableAppConfiguration.create(
        exportedAt: DateTime.utc(2026, 8, 7),
        appVersion: 'phone-web',
        tmdbApiKey: '',
        cloudSources: const <PortableCloudSourceConfiguration>[],
      ),
      fileIds: const <TvPairingFileKind, String>{
        TvPairingFileKind.configuration: 'config-id',
        TvPairingFileKind.scrapedMetadata: 'metadata-id',
      },
      uploadedFiles: const <TvPairingFileKind, TvPairingUploadedFile>{
        TvPairingFileKind.configuration: TvPairingUploadedFile(
          id: 'config-id',
          kind: TvPairingFileKind.configuration,
          name: 'config.kyyconfig',
          size: 3,
          path: 'config-path',
        ),
        TvPairingFileKind.scrapedMetadata: TvPairingUploadedFile(
          id: 'metadata-id',
          kind: TvPairingFileKind.scrapedMetadata,
          name: 'metadata.kyymeta',
          size: 3,
          path: 'metadata-path',
        ),
      },
      configurationFilePassword: 'password-secret',
    );

class _FakePairingServer implements TvPairingServer {
  TvPairingSession? session;
  TvPairingPhoneConnectedHandler? phoneConnectedHandler;
  TvPairingPayloadHandler? payloadHandler;
  TvPairingCancelledHandler? cancelledHandler;
  int stopCount = 0;

  @override
  bool get isRunning => session != null;

  @override
  Future<TvPairingServerEndpoint> start({
    required TvPairingSession session,
    required TvPairingPhoneConnectedHandler onPhoneConnected,
    required TvPairingPayloadHandler onPayload,
    TvPairingCancelledHandler? onCancelled,
  }) async {
    this.session = session;
    phoneConnectedHandler = onPhoneConnected;
    payloadHandler = onPayload;
    cancelledHandler = onCancelled;
    return TvPairingServerEndpoint(
      host: '192.168.1.20',
      port: 45678,
      pairingToken: session.token,
    );
  }

  void notifyPhoneConnected() => phoneConnectedHandler?.call();

  Future<TvPairingSubmissionResult> submit(TvPairingPayload payload) =>
      payloadHandler!(payload);

  @override
  Future<void> stop() async {
    stopCount++;
    session = null;
    phoneConnectedHandler = null;
    payloadHandler = null;
    cancelledHandler = null;
  }
}

class _FailingConfigurationImporter implements ConfigurationImportPort {
  const _FailingConfigurationImporter();

  @override
  Future<ConfigurationImportResult> apply(
    PortableAppConfiguration configuration,
  ) async {
    throw const ConfigurationImportException();
  }

  @override
  Future<ConfigurationMergeSummary> preview(
    PortableAppConfiguration configuration,
  ) async =>
      const ConfigurationMergeSummary(
        added: 1,
        updated: 0,
        preserved: 0,
        tmdbWillUpdate: true,
        requiresRootSelection: 0,
      );
}

class _FakeTvPairingFileImporter implements TvPairingFileImportPort {
  int previewCount = 0;
  int applyCount = 0;

  @override
  Future<TvPairingFileImportPreview> preview(TvPairingPayload payload) async {
    previewCount++;
    return const TvPairingFileImportPreview(
      configurationSummary: ConfigurationMergeSummary(
        added: 0,
        updated: 0,
        preserved: 0,
        tmdbWillUpdate: false,
        requiresRootSelection: 0,
      ),
      hasConfigurationFile: true,
      hasScrapedMetadataFile: true,
      metadataMatchedCount: 10,
      metadataMissingMediaCount: 1,
      metadataRecoverableImageCount: 2,
    );
  }

  @override
  Future<TvPairingFileImportResult> apply(TvPairingPayload payload) async {
    applyCount++;
    return const TvPairingFileImportResult(
      configurationSummary: ConfigurationMergeSummary(
        added: 0,
        updated: 0,
        preserved: 0,
        tmdbWillUpdate: false,
        requiresRootSelection: 0,
      ),
      metadataResult: ScrapedMetadataTransferResult(
        localCount: 1,
        cloudCount: 2,
        imageCount: 2,
        skippedCount: 1,
      ),
    );
  }
}
