import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv_pairing/application/tv_pairing_controller.dart';
import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_http_server.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';
import 'package:kanyingyin/features/tv_pairing/presentation/tv_pairing_page.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

void main() {
  testWidgets('配对页显示二维码、局域网地址和手动配置入口', (tester) async {
    await _setTvViewport(tester);
    final fixture = await _PairingPageFixture.create();

    await tester.pumpWidget(MaterialApp(
      home: TvPairingPage(controller: fixture.controller),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('tv-pairing-qr')), findsOneWidget);
    expect(find.textContaining('192.168.1.20'), findsOneWidget);
    expect(find.text('取消配对'), findsOneWidget);
    expect(find.text('手动配置'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('tv-pairing-countdown')),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('手机提交后由 TV 确认且界面不展示敏感值', (tester) async {
    await _setTvViewport(tester);
    final fixture = await _PairingPageFixture.create();
    await tester.pumpWidget(MaterialApp(
      home: TvPairingPage(controller: fixture.controller),
    ));
    await tester.pumpAndSettle();

    final submission = fixture.server.submit(_payload());
    await tester.pumpAndSettle();

    expect(find.text('确认手机配置'), findsOneWidget);
    expect(find.text('网盘来源：1 个'), findsOneWidget);
    expect(find.text('TMDB：将更新'), findsOneWidget);
    expect(find.textContaining('secret-password'), findsNothing);
    expect(find.textContaining('secret-tmdb-key'), findsNothing);

    await tester.tap(find.text('确认写入'));
    await tester.pumpAndSettle();

    expect(await submission, TvPairingSubmissionResult.accepted);
    expect(find.text('配置已写入'), findsOneWidget);
    expect(fixture.tmdbManager.exportForPairing(), 'secret-tmdb-key');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Future<void> _setTvViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

TvPairingPayload _payload() => const TvPairingPayload(
      protocolVersion: TvPairingPayload.currentProtocolVersion,
      deviceName: '手机配置',
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

class _PairingPageFixture {
  const _PairingPageFixture({
    required this.controller,
    required this.server,
    required this.tmdbManager,
  });

  final TvPairingController controller;
  final _FakePairingServer server;
  final TmdbCredentialManager tmdbManager;

  static Future<_PairingPageFixture> create() async {
    final credentialStore = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
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
    final server = _FakePairingServer();
    return _PairingPageFixture(
      server: server,
      tmdbManager: tmdbManager,
      controller: TvPairingController(
        sourceRepository: repository,
        tmdbCredentialManager: tmdbManager,
        server: server,
        now: () => DateTime.utc(2026, 8, 6, 12),
      ),
    );
  }
}

class _FakePairingServer implements TvPairingServer {
  TvPairingSession? session;
  TvPairingPayloadHandler? payloadHandler;

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
    session = null;
    payloadHandler = null;
  }
}
