import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/features/tv_pairing/application/tv_pairing_controller.dart';
import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_http_server.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';
import 'package:kanyingyin/features/tv_pairing/presentation/tv_pairing_page.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

void main() {
  testWidgets('配对页操作按钮使用 TV 高对比焦点表面', (tester) async {
    installAppPlatformCapabilities(
      AppPlatformCapabilities.android.copyWith(television: true),
    );
    addTearDown(
      () => installAppPlatformCapabilities(AppPlatformCapabilities.windows),
    );
    await _setTvViewport(tester);
    final fixture = await _PairingPageFixture.create();
    await tester.pumpWidget(MaterialApp(
      home: TvPairingPage(controller: fixture.controller),
    ));
    await _waitFor(tester, find.byKey(const ValueKey<String>('tv-pairing-qr')));

    expect(
      find.byKey(const ValueKey<String>('tv-pairing-cancel-focus')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('tv-pairing-manual-focus')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('配对页显示二维码、局域网地址和手动配置入口', (tester) async {
    await _setTvViewport(tester);
    final fixture = await _PairingPageFixture.create();

    await tester.pumpWidget(MaterialApp(
      home: TvPairingPage(controller: fixture.controller),
    ));
    await _waitFor(tester, find.byKey(const ValueKey<String>('tv-pairing-qr')));

    expect(find.byKey(const ValueKey<String>('tv-pairing-qr')), findsOneWidget);
    expect(find.textContaining('192.168.1.20'), findsOneWidget);
    expect(find.text('取消配对'), findsOneWidget);
    expect(find.text('手动配置'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('tv-pairing-countdown')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('手机打开后隐藏主二维码并显示连接成功', (tester) async {
    await _setTvViewport(tester);
    final fixture = await _PairingPageFixture.create();
    await tester.pumpWidget(MaterialApp(
      home: TvPairingPage(controller: fixture.controller),
    ));
    await _waitFor(tester, find.byKey(const ValueKey<String>('tv-pairing-qr')));

    fixture.server.notifyPhoneConnected();
    await _waitFor(tester, find.text('手机已连接'));
    await _waitForAbsent(
      tester,
      find.byKey(const ValueKey<String>('tv-pairing-qr')),
    );

    expect(find.byKey(const ValueKey<String>('tv-pairing-qr')), findsNothing);
    expect(find.text('手机已连接'), findsOneWidget);
    expect(find.text('等待手机填写并发送配置'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('手机提交后由 TV 确认且界面不展示敏感值', (tester) async {
    await _setTvViewport(tester);
    final fixture = await _PairingPageFixture.create();
    await tester.pumpWidget(MaterialApp(
      home: TvPairingPage(controller: fixture.controller),
    ));
    await _waitFor(tester, find.byKey(const ValueKey<String>('tv-pairing-qr')));

    final submission = fixture.server.submit(_openListPayload());
    await _waitFor(tester, find.text('确认手机配置'));

    expect(find.text('确认手机配置'), findsOneWidget);
    expect(find.text('网盘来源：1 个'), findsOneWidget);
    expect(find.text('新增来源：1 个'), findsOneWidget);
    expect(find.text('TMDB：将更新'), findsOneWidget);
    expect(find.textContaining('secret-password'), findsNothing);
    expect(find.textContaining('secret-tmdb-key'), findsNothing);

    await tester.tap(find.text('确认写入'));
    await _waitFor(tester, find.text('配置已写入'));

    expect(await submission, TvPairingSubmissionResult.accepted);
    expect(find.text('配置已写入'), findsOneWidget);
    expect(fixture.tmdbManager.exportForPairing(), 'secret-tmdb-key');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('成功页提示未选择目录的来源且返回前刷新列表', (tester) async {
    await _setTvViewport(tester);
    final fixture = await _PairingPageFixture.create();
    var reloadCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: TvPairingPage(
        controller: fixture.controller,
        onCompleted: () async => reloadCount++,
      ),
    ));
    await _waitFor(tester, find.byKey(const ValueKey<String>('tv-pairing-qr')));

    final submission = fixture.server.submit(_quarkPayloadWithoutRoot());
    await _waitFor(tester, find.text('需要选择媒体目录：1 个'));
    await tester.tap(find.text('确认写入'));
    await _waitFor(tester, find.text('返回网盘数据源选择目录'));

    expect(await submission, TvPairingSubmissionResult.accepted);
    expect(find.text('返回网盘数据源选择目录'), findsOneWidget);
    await tester.tap(find.text('返回网盘数据源选择目录'));
    await tester.pump();
    expect(reloadCount, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('TV 拒绝后恢复等待手机修改而不是退出页面', (tester) async {
    await _setTvViewport(tester);
    final fixture = await _PairingPageFixture.create();
    await tester.pumpWidget(MaterialApp(
      home: TvPairingPage(controller: fixture.controller),
    ));
    await _waitFor(tester, find.byKey(const ValueKey<String>('tv-pairing-qr')));
    fixture.server.notifyPhoneConnected();
    await _waitFor(tester, find.text('手机已连接'));

    final submission = fixture.server.submit(_openListPayload());
    await _waitFor(tester, find.text('确认手机配置'));
    await tester.tap(find.text('拒绝'));
    await _waitFor(tester, find.text('等待手机填写并发送配置'));

    expect(await submission, TvPairingSubmissionResult.rejected);
    expect(find.text('手机已连接'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('等待配对页面状态超时：$finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForAbsent(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('等待配对页面状态消失超时：$finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _setTvViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

TvPairingPayload _openListPayload() => TvPairingPayload(
      protocolVersion: TvPairingPayload.currentProtocolVersion,
      deviceName: '手机配置',
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

TvPairingPayload _quarkPayloadWithoutRoot() => TvPairingPayload(
      protocolVersion: TvPairingPayload.currentProtocolVersion,
      deviceName: '手机配置',
      configuration: PortableAppConfiguration.create(
        exportedAt: DateTime.utc(2026, 8, 7),
        appVersion: 'phone-web',
        tmdbApiKey: '',
        cloudSources: <PortableCloudSourceConfiguration>[
          PortableCloudSourceConfiguration.fromSource(
            source: const CloudSource(
              id: 'quark-1',
              type: CloudSourceType.quark,
              name: '夸克网盘',
              baseUrl: 'https://pan.quark.cn',
              rootPaths: <String>[],
            ),
            credential: const CloudCredential(cookie: 'cookie-secret'),
          ),
        ],
      ),
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
        importer: ConfigurationImporter(
          sourceRepository: repository,
          tmdbCredentialManager: tmdbManager,
        ),
        server: server,
        now: () => DateTime.utc(2026, 8, 6, 12),
      ),
    );
  }
}

class _FakePairingServer implements TvPairingServer {
  TvPairingSession? session;
  TvPairingPhoneConnectedHandler? phoneConnectedHandler;
  TvPairingPayloadHandler? payloadHandler;

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
    session = null;
    phoneConnectedHandler = null;
    payloadHandler = null;
  }
}
