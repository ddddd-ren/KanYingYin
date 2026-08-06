import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv_pairing/application/tv_pairing_controller.dart';
import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_http_server.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryCloudSourceStorage sourceStorage;
  late MemoryCloudCredentialStore credentialStore;
  late CloudSourceRepository repository;
  late MemoryTmdbCredentialStore tmdbStore;
  late TmdbCredentialManager tmdbManager;
  late _FakePairingServer server;
  late TvPairingController controller;

  setUp(() async {
    sourceStorage = MemoryCloudSourceStorage();
    credentialStore = MemoryCloudCredentialStore();
    repository = CloudSourceRepository(
      storage: sourceStorage,
      credentialStore: credentialStore,
    );
    tmdbStore = MemoryTmdbCredentialStore('old-tmdb-key');
    tmdbManager = TmdbCredentialManager(
      store: tmdbStore,
      legacyReader: () => '',
      legacyDelete: () async {},
      warningLogger: (_) {},
    );
    await tmdbManager.initialize();
    server = _FakePairingServer();
    controller = TvPairingController(
      sourceRepository: repository,
      tmdbCredentialManager: tmdbManager,
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

  test('TV 确认后写入 TMDB 与强类型网盘配置', () async {
    await controller.start();
    final submission = server.submit(_payload());
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, TvPairingState.awaitingConfirmation);
    expect(controller.pendingSummary?.cloudSourceCount, 1);
    expect(controller.pendingSummary.toString(),
        isNot(contains('secret-password')));
    expect(controller.pendingSummary.toString(),
        isNot(contains('secret-tmdb-key')));

    await controller.confirmPending();

    expect(await submission, TvPairingSubmissionResult.accepted);
    expect(controller.state, TvPairingState.success);
    expect(tmdbManager.exportForPairing(), 'secret-tmdb-key');
    expect((await repository.getById('cloud-1'))?.name, '家庭网盘');
    expect(
      (await credentialStore.read('cloud-1'))?.password,
      'secret-password',
    );
  });

  test('TV 拒绝后不写入配置且会话继续有效', () async {
    await controller.start();
    final submission = server.submit(_payload());
    await Future<void>.delayed(Duration.zero);

    controller.rejectPending();

    expect(await submission, TvPairingSubmissionResult.rejected);
    expect(controller.state, TvPairingState.active);
    expect(tmdbManager.exportForPairing(), 'old-tmdb-key');
    expect(await repository.getAll(), isEmpty);
    expect(server.session?.isConsumed, isFalse);
  });

  test('来源写入失败时恢复 TMDB 且不接受配对', () async {
    controller.dispose();
    controller = TvPairingController(
      sourceRepository: _FailingPairingRepository(),
      tmdbCredentialManager: tmdbManager,
      server: server,
      now: () => DateTime.utc(2026, 8, 6, 12),
    );
    await controller.start();
    final submission = server.submit(_payload());
    await Future<void>.delayed(Duration.zero);

    await controller.confirmPending();

    expect(await submission, TvPairingSubmissionResult.rejected);
    expect(controller.state, TvPairingState.error);
    expect(controller.errorMessage, '配置写入失败，请重试');
    expect(tmdbManager.exportForPairing(), 'old-tmdb-key');
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
}

TvPairingPayload _payload() => const TvPairingPayload(
      protocolVersion: TvPairingPayload.currentProtocolVersion,
      deviceName: '客厅电视',
      tmdbApiKey: 'secret-tmdb-key',
      cloudSources: <TvPairingCloudSourceRecord>[
        TvPairingCloudSourceRecord(
          source: CloudSource(
            id: 'cloud-1',
            type: CloudSourceType.openList,
            name: '家庭网盘',
            baseUrl: 'https://cloud.example.com',
            rootPaths: <String>['/电影'],
          ),
          credential: CloudCredential(password: 'secret-password'),
        ),
      ],
    );

class _FakePairingServer implements TvPairingServer {
  TvPairingSession? session;
  TvPairingPayloadHandler? payloadHandler;
  TvPairingCancelledHandler? cancelledHandler;
  int stopCount = 0;

  @override
  bool get isRunning => session != null;

  @override
  Future<TvPairingServerEndpoint> start({
    required TvPairingSession session,
    required TvPairingPayloadHandler onPayload,
    TvPairingCancelledHandler? onCancelled,
  }) async {
    this.session = session;
    payloadHandler = onPayload;
    cancelledHandler = onCancelled;
    return TvPairingServerEndpoint(
      host: '192.168.1.20',
      port: 45678,
      pairingToken: session.token,
    );
  }

  Future<TvPairingSubmissionResult> submit(TvPairingPayload payload) =>
      payloadHandler!(payload);

  @override
  Future<void> stop() async {
    stopCount++;
    session = null;
    payloadHandler = null;
    cancelledHandler = null;
  }
}

class _FailingPairingRepository extends CloudSourceRepository {
  _FailingPairingRepository()
      : super(
          storage: MemoryCloudSourceStorage(),
          credentialStore: MemoryCloudCredentialStore(),
        );

  @override
  Future<void> importForPairing(List<CloudSourcePairingEntry> entries) async {
    throw StateError('模拟来源写入失败');
  }
}
