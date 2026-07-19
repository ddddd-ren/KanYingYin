import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_subtitle_cache.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/modules/local/local_episode.dart';
import 'package:kanyingyin/modules/video/local_playback_session.dart';

void main() {
  late CloudSource source;
  late CloudSourceRepository repository;

  setUp(() async {
    source = CloudSource(
      id: 'openlist-home',
      name: '家庭网盘',
      type: CloudSourceType.openList,
      baseUrl: 'https://drive.example.com',
      rootPaths: const ['/'],
    );
    repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
  });

  test('点击解析时才创建客户端并透传实时地址与请求头', () async {
    var factoryCalls = 0;
    final client = _FakeClient(
      resource: CloudPlaybackResource(
        uri: Uri.parse('https://cdn.example.com/live-token'),
        headers: const {'Authorization': 'Bearer token'},
        networkRoute: PlaybackNetworkRoute.direct,
      ),
    );
    final resolver = CloudPlaybackResolver(
      sourceRepository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      clientFactory: (_, __, ___) {
        factoryCalls++;
        return client;
      },
    );

    expect(factoryCalls, 0);
    final result = await resolver.resolve(
      const CloudPlaybackTarget(
        sourceId: 'openlist-home',
        remotePath: '/Show/E01.mkv',
        stableId: 'episode-1',
        title: '第 1 集',
      ),
    );

    expect(factoryCalls, 1);
    expect(client.authenticateCalls, 0);
    expect(result.videoUrl, 'https://cdn.example.com/live-token');
    expect(result.httpHeaders, {'Authorization': 'Bearer token'});
    expect(result.networkRoute, PlaybackNetworkRoute.direct);
    expect(result.cloudProviderName, 'OpenList');
    expect(client.closed, isTrue);
  });

  test('解析失败也会关闭客户端', () async {
    final client = _FakeClient(error: StateError('解析失败'));
    final resolver = CloudPlaybackResolver(
      sourceRepository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      clientFactory: (_, __, ___) => client,
    );

    await expectLater(
      resolver.resolve(const CloudPlaybackTarget(
        sourceId: 'openlist-home',
        remotePath: '/Show/E01.mkv',
        stableId: 'episode-1',
        title: '第 1 集',
      )),
      throwsA(isA<StateError>()),
    );
    expect(client.closed, isTrue);
  });

  test('远程字幕下载失败时视频仍可播放', () async {
    final root = await Directory.systemTemp.createTemp('cloud-playback-');
    addTearDown(() => root.delete(recursive: true));
    final client = _FakeClient(
      resource: CloudPlaybackResource(uri: Uri.parse('https://cdn/video')),
      subtitle: const CloudFileEntry(
        id: 'sub-1',
        name: 'E01.ass',
        remotePath: '/Show/E01.ass',
        isDirectory: false,
        size: 100,
        modifiedAt: null,
      ),
    );
    final resolver = CloudPlaybackResolver(
      sourceRepository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      clientFactory: (_, __, ___) => client,
      subtitleCache: CloudSubtitleCache(
        cacheRoot: root,
        downloader: (_) async => throw const SocketException('断网'),
      ),
    );

    final result = await resolver.resolve(const CloudPlaybackTarget(
      sourceId: 'openlist-home',
      remotePath: '/Show/E01.mkv',
      stableId: 'episode-1',
      title: '第 1 集',
      subtitleRemotePath: '/Show/E01.ass',
    ));

    expect(result.videoUrl, 'https://cdn/video');
    expect(result.subtitlePath, isNull);
    expect(client.closed, isTrue);
  });

  test('远程字幕偏移 key 按来源和规范化路径隔离', () {
    expect(
      cloudSubtitleOffsetKey('source-a', r'/Show/../Show/E01.MKV'),
      'cloud:source-a:/show/e01.mkv',
    );
    expect(
      cloudSubtitleOffsetKey('source-b', '/Show/E01.mkv'),
      isNot(cloudSubtitleOffsetKey('source-a', '/Show/E01.mkv')),
    );
  });

  test('只对明确鉴权、权限或签名过期错误刷新', () {
    expect(
        shouldRefreshCloudLink(const CloudPlaybackHttpException(401)), isTrue);
    expect(
        shouldRefreshCloudLink(const CloudPlaybackHttpException(403)), isTrue);
    expect(
      shouldRefreshCloudLink(
        const CloudDriveException(CloudDriveErrorType.expiredLink),
      ),
      isTrue,
    );
    expect(shouldRefreshCloudLink(Exception('decoder returned 403 frames')),
        isFalse);
    expect(
        shouldRefreshCloudLink(const CloudPlaybackHttpException(500)), isFalse);
    expect(
      shouldRefreshCloudLink('Failed to open https://cdn.example.com'),
      isTrue,
    );
    expect(shouldRefreshCloudLink('decoder initialization failed'), isFalse);
    expect(
      cloudPlaybackFailureMessage('夸克'),
      '夸克播放地址不可用，请重新登录或稍后重试',
    );
    expect(
      cloudPlaybackFailureMessage(null),
      '网盘播放地址不可用，请重新登录或稍后重试',
    );
  });

  test('同来源播放列表切集时重新解析对应远程路径', () async {
    final resolvedPaths = <String>[];
    final controller = LocalVideoController(
      resolveCloudPlayback: (target) async {
        resolvedPaths.add(target.remotePath);
        return CloudResolvedPlayback(
          target: target,
          videoUrl: 'https://cdn${target.remotePath}',
          httpHeaders: const {'Referer': 'https://drive.example.com'},
        );
      },
      initializePlayer: (_) async {},
    );
    await controller.openCloudPlayback(
      seriesTitle: '测试动画',
      targets: const [
        CloudPlaybackTarget(
          sourceId: 'openlist-home',
          remotePath: '/Show/E01.mkv',
          stableId: 'e1',
          title: '第 1 集',
        ),
        CloudPlaybackTarget(
          sourceId: 'openlist-home',
          remotePath: '/Show/E02.mkv',
          stableId: 'e2',
          title: '第 2 集',
        ),
      ],
      selectedStableId: 'e1',
    );

    await controller.changeEpisode(1);
    await controller.changeEpisode(2);

    expect(resolvedPaths, ['/Show/E01.mkv', '/Show/E02.mkv']);
    expect(controller.roadList.single.data, ['/Show/E01.mkv', '/Show/E02.mkv']);
  });

  test('首次打开在返回前解析且首帧消费预解析结果', () async {
    var resolveCalls = 0;
    final initialized = <PlaybackInitParams>[];
    final controller = LocalVideoController(
      resolveCloudPlayback: (target) async {
        resolveCalls++;
        return CloudResolvedPlayback(
          target: target,
          videoUrl: 'https://cdn/first',
          httpHeaders: const {'X-Token': 'first'},
          networkRoute: PlaybackNetworkRoute.direct,
          cloudProviderName: '夸克',
        );
      },
      initializePlayer: (params) async => initialized.add(params),
    );

    await controller.openCloudPlayback(
      seriesTitle: '测试动画',
      targets: const [
        CloudPlaybackTarget(
          sourceId: 'openlist-home',
          remotePath: '/Show/E01.mkv',
          stableId: 'e1',
          title: '第 1 集',
        )
      ],
      selectedStableId: 'e1',
    );
    expect(resolveCalls, 1);
    expect(initialized, isEmpty);

    await controller.changeEpisode(1);
    expect(resolveCalls, 1);
    expect(initialized.single.offset, 0);
    expect(initialized.single.httpHeaders, {'X-Token': 'first'});
    expect(initialized.single.networkRoute, PlaybackNetworkRoute.direct);
    expect(initialized.single.cloudProviderName, '夸克');
  });

  test('首次解析失败时不初始化播放器', () async {
    var initialized = false;
    final controller = LocalVideoController(
      resolveCloudPlayback: (_) async => throw StateError('解析失败'),
      initializePlayer: (_) async => initialized = true,
    );

    await expectLater(
      controller.openCloudPlayback(
        seriesTitle: '测试动画',
        targets: const [
          CloudPlaybackTarget(
            sourceId: 'openlist-home',
            remotePath: '/Show/E01.mkv',
            stableId: 'e1',
            title: '第 1 集',
          )
        ],
        selectedStableId: 'e1',
      ),
      throwsStateError,
    );
    expect(initialized, isFalse);
  });

  test('刷新链接沿用旧有效字幕并替换地址和请求头', () {
    final target = const CloudPlaybackTarget(
      sourceId: 'openlist-home',
      remotePath: '/Show/E01.mkv',
      stableId: 'e1',
      title: '第 1 集',
    );
    PlaybackInitParams params({
      required String url,
      String? subtitle,
      PlaybackNetworkRoute networkRoute = PlaybackNetworkRoute.inheritProxy,
    }) =>
        PlaybackInitParams(
          videoUrl: url,
          offset: 0,
          isLocalPlayback: false,
          bangumiId: 1,
          pluginName: '网盘媒体库',
          episode: 1,
          httpHeaders: {'Token': url},
          adBlockerEnabled: false,
          episodeTitle: target.title,
          referer: '',
          currentRoad: 0,
          subtitlePath: subtitle,
          networkRoute: networkRoute,
        );

    final merged = mergeRefreshedCloudPlayback(
      previous: params(url: 'old', subtitle: r'C:\cache\old.ass'),
      refreshed: params(
        url: 'new',
        networkRoute: PlaybackNetworkRoute.direct,
      ),
      position: const Duration(seconds: 42),
    );
    expect(merged.videoUrl, 'new');
    expect(merged.httpHeaders, {'Token': 'new'});
    expect(merged.subtitlePath, r'C:\cache\old.ass');
    expect(merged.offset, 42);
    expect(merged.networkRoute, PlaybackNetworkRoute.direct);
  });

  test('播放器只为继承策略应用已启用的 HTTP 代理', () {
    expect(
      shouldApplyPlayerProxy(
        proxyEnabled: true,
        networkRoute: PlaybackNetworkRoute.direct,
      ),
      isFalse,
    );
    expect(
      shouldApplyPlayerProxy(
        proxyEnabled: true,
        networkRoute: PlaybackNetworkRoute.inheritProxy,
      ),
      isTrue,
    );
    expect(
      shouldApplyPlayerProxy(
        proxyEnabled: false,
        networkRoute: PlaybackNetworkRoute.inheritProxy,
      ),
      isFalse,
    );
  });

  test('切集解析乱序时只有最新请求可以提交', () {
    final coordinator = CloudPlaybackOperationCoordinator();
    final session = coordinator.beginSession();
    final episode2 = coordinator.beginRequest(session);
    final episode3 = coordinator.beginRequest(session);
    expect(coordinator.isCurrent(episode2), isFalse);
    expect(coordinator.isCurrent(episode3), isTrue);
  });

  test('两个打开请求乱序时旧会话不能覆盖新会话', () {
    final coordinator = CloudPlaybackOperationCoordinator();
    final oldSession = coordinator.beginSession();
    final oldRequest = coordinator.beginRequest(oldSession);
    final newSession = coordinator.beginSession();
    final newRequest = coordinator.beginRequest(newSession);
    expect(coordinator.isCurrent(oldRequest), isFalse);
    expect(coordinator.isCurrent(newRequest), isTrue);
  });

  test('导航协调器拒绝重复入口且旧请求不能导航', () {
    final coordinator = CloudPlaybackNavigationCoordinator();
    final first = coordinator.tryBegin();
    expect(first, isNotNull);
    expect(coordinator.tryBegin(), isNull);
    coordinator.finish(first!);
    final second = coordinator.tryBegin();
    expect(second, isNotNull);
    expect(coordinator.isCurrent(first), isFalse);
    expect(coordinator.isCurrent(second!), isTrue);
  });

  test('媒体描述不泄露查询签名和用户信息', () {
    final description = sanitizeMediaDescription(
      'https://user:password@cdn.example.com/video.mkv?signature=secret&token=x',
      isLocalPlayback: false,
    );
    expect(description, 'https://cdn.example.com');
    expect(description, isNot(contains('secret')));
    expect(
      sanitizeMediaDescription(r'C:\Private\movie.mkv', isLocalPlayback: true),
      'movie.mkv',
    );
  });

  test('播放器诊断文本不泄露远程媒体签名', () {
    const secretUrl =
        'https://user:password@cdn.example.com/video/episode.mkv?signature=secret&token=x';
    final logText = sanitizeMediaDiagnosticText(
      'PlayerLog(prefix: ffmpeg, text: Opening $secretUrl)',
      isLocalPlayback: false,
    );
    final sourceText = sanitizeMediaDiagnosticText(
      secretUrl,
      isLocalPlayback: false,
    );

    for (final text in [logText, sourceText]) {
      expect(text, contains('https://cdn.example.com'));
      expect(text, isNot(contains('episode.mkv')));
      expect(text, isNot(contains('signature')));
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('password')));
    }
    expect(logText, startsWith('PlayerLog(prefix: ffmpeg'));
  });

  test('播放器诊断文本保留本地调试信息', () {
    const localPlaylist =
        r'Playlist(medias: [Media(C:\Videos\Anime\episode.mkv)], index: 0)';
    expect(
      sanitizeMediaDiagnosticText(
        localPlaylist,
        isLocalPlayback: true,
      ),
      localPlaylist,
    );
  });

  test('播放器协调器忽略旧媒体错误且刷新单飞', () {
    final coordinator = PlayerMediaOperationCoordinator();
    final oldMedia = coordinator.beginMedia('old');
    final currentMedia = coordinator.beginMedia('new');
    expect(
      coordinator.tryBeginRefresh(
        oldMedia,
        const CloudPlaybackHttpException(403),
      ),
      isFalse,
    );
    expect(
      coordinator.tryBeginRefresh(
        currentMedia,
        const CloudPlaybackHttpException(403),
      ),
      isTrue,
    );
    expect(
      coordinator.tryBeginRefresh(
        currentMedia,
        const CloudPlaybackHttpException(403),
      ),
      isFalse,
    );
    coordinator.finishRefresh(currentMedia);
    expect(
      coordinator.tryBeginRefresh(
        currentMedia,
        const CloudPlaybackHttpException(403),
      ),
      isFalse,
    );
  });

  test('初始化等待执行时退出会同步使token失效且不创建资源', () async {
    final coordinator = PlayerMediaOperationCoordinator();
    final token = coordinator.beginMedia('video');
    final releaseLock = Completer<void>();
    var createCalls = 0;
    final pending = () async {
      await releaseLock.future;
      if (!coordinator.isCurrent(token)) return;
      createCalls++;
    }();
    coordinator.invalidate();
    releaseLock.complete();
    await pending;
    expect(createCalls, 0);
  });

  test('创建进行中退出会在创建完成后立即释放资源', () async {
    final coordinator = PlayerMediaOperationCoordinator();
    final token = coordinator.beginMedia('video');
    final created = Completer<String>();
    final disposed = <String>[];
    final pending = () async {
      final resource = await created.future;
      if (!coordinator.isCurrent(token)) disposed.add(resource);
    }();
    coordinator.invalidate();
    created.complete('player');
    await pending;
    expect(disposed, ['player']);
  });

  test('内部换媒体建立新token且重复退出安全', () {
    final coordinator = PlayerMediaOperationCoordinator();
    final oldToken = coordinator.beginMedia('old');
    final newToken = coordinator.beginMedia('new');
    expect(coordinator.isCurrent(oldToken), isFalse);
    expect(coordinator.isCurrent(newToken), isTrue);
    coordinator.invalidate();
    coordinator.invalidate();
    expect(coordinator.isCurrent(newToken), isFalse);
  });

  test('播放器生命周期退出后旧token失效且新页面可重新激活', () {
    final coordinator = PlayerLifecycleCoordinator();
    final oldPage = coordinator.activate();
    var createCalls = 0;
    void createFor(PlayerLifecycleToken token) {
      if (coordinator.isCurrent(token)) createCalls++;
    }

    expect(coordinator.isCurrent(oldPage), isTrue);
    coordinator.invalidate();
    createFor(oldPage);
    expect(coordinator.isCurrent(oldPage), isFalse);
    final newPage = coordinator.activate();
    createFor(newPage);
    expect(coordinator.isCurrent(newPage), isTrue);
    expect(coordinator.isCurrent(oldPage), isFalse);
    expect(createCalls, 1);
  });

  test('本地换集等待停止时退出则放行后不调用播放器初始化', () async {
    final releaseStop = Completer<void>();
    var initializeCalls = 0;
    final controller = LocalVideoController(
      initializePlayer: (_) async => initializeCalls++,
    );
    controller.openSession(LocalPlaybackSession(
      seriesId: 'local',
      seriesTitle: '本地',
      episodes: const [
        LocalEpisode(id: '1', path: '1.mkv', title: '1'),
        LocalEpisode(id: '2', path: '2.mkv', title: '2'),
      ],
      currentEpisodeId: '1',
    ));

    final change = () async {
      await releaseStop.future;
      await controller.changeEpisode(2);
    }();
    controller.invalidatePlaybackOperations();
    releaseStop.complete();
    await change;

    expect(initializeCalls, 0);
    expect(controller.currentEpisode, 1);
    expect(controller.session.currentEpisodeId, '1');
  });

  test('本地切集异步完成后若播放会话已退出则不提交旧集状态', () async {
    final release = Completer<void>();
    final controller = LocalVideoController(
      initializePlayer: (_) => release.future,
    );
    controller.openSession(LocalPlaybackSession(
      seriesId: 'local',
      seriesTitle: '本地',
      episodes: const [
        LocalEpisode(id: '1', path: '1.mkv', title: '1'),
        LocalEpisode(id: '2', path: '2.mkv', title: '2'),
      ],
      currentEpisodeId: '1',
    ));
    final change = controller.changeEpisode(2);
    controller.invalidatePlaybackOperations();
    release.complete();
    await change;
    expect(controller.currentEpisode, 1);
    expect(controller.session.currentEpisodeId, '1');
  });

  test('控制器丢弃乱序切集解析结果', () async {
    final episode2 = Completer<CloudResolvedPlayback>();
    final episode3 = Completer<CloudResolvedPlayback>();
    final initialized = <String>[];
    final targets = const [
      CloudPlaybackTarget(
          sourceId: 's', remotePath: '/1.mkv', stableId: '1', title: '1'),
      CloudPlaybackTarget(
          sourceId: 's', remotePath: '/2.mkv', stableId: '2', title: '2'),
      CloudPlaybackTarget(
          sourceId: 's', remotePath: '/3.mkv', stableId: '3', title: '3'),
    ];
    final controller = LocalVideoController(
      resolveCloudPlayback: (target) {
        if (target.stableId == '2') return episode2.future;
        if (target.stableId == '3') return episode3.future;
        return Future.value(CloudResolvedPlayback(
            target: target, videoUrl: 'https://cdn/1', httpHeaders: const {}));
      },
      initializePlayer: (params) async => initialized.add(params.videoUrl),
    );
    await controller.openCloudPlayback(
        seriesTitle: 'S', targets: targets, selectedStableId: '1');
    await controller.changeEpisode(1);
    final second = controller.changeEpisode(2);
    final third = controller.changeEpisode(3);
    episode3.complete(CloudResolvedPlayback(
        target: targets[2], videoUrl: 'https://cdn/3', httpHeaders: const {}));
    await third;
    episode2.complete(CloudResolvedPlayback(
        target: targets[1], videoUrl: 'https://cdn/2', httpHeaders: const {}));
    await second;
    expect(controller.currentEpisode, 3);
    expect(initialized, ['https://cdn/1', 'https://cdn/3']);
  });

  test('控制器丢弃较晚完成的旧打开请求', () async {
    final oldResult = Completer<CloudResolvedPlayback>();
    final newResult = Completer<CloudResolvedPlayback>();
    final controller = LocalVideoController(
      resolveCloudPlayback: (target) =>
          target.sourceId == 'old' ? oldResult.future : newResult.future,
      initializePlayer: (_) async {},
    );
    const oldTarget = CloudPlaybackTarget(
        sourceId: 'old', remotePath: '/old.mkv', stableId: 'old', title: '旧');
    const newTarget = CloudPlaybackTarget(
        sourceId: 'new', remotePath: '/new.mkv', stableId: 'new', title: '新');
    final oldOpen = controller.openCloudPlayback(
        seriesTitle: '旧系列',
        targets: const [oldTarget],
        selectedStableId: 'old');
    final newOpen = controller.openCloudPlayback(
        seriesTitle: '新系列',
        targets: const [newTarget],
        selectedStableId: 'new');
    newResult.complete(const CloudResolvedPlayback(
        target: newTarget, videoUrl: 'https://new', httpHeaders: {}));
    await newOpen;
    oldResult.complete(const CloudResolvedPlayback(
        target: oldTarget, videoUrl: 'https://old', httpHeaders: {}));
    await oldOpen;
    expect(controller.title, '新系列');
  });

  test('刷新事务保留暂停态和进度', () {
    final transaction = CloudPlaybackRefreshTransaction(
      previous: PlaybackInitParams(
        videoUrl: 'old',
        offset: 0,
        isLocalPlayback: false,
        bangumiId: 1,
        pluginName: '网盘媒体库',
        episode: 1,
        httpHeaders: const {},
        adBlockerEnabled: false,
        episodeTitle: '1',
        referer: '',
        currentRoad: 0,
      ),
      position: const Duration(seconds: 31),
      wasPlaying: false,
    );
    expect(transaction.shouldPauseAfterRefresh, isTrue);
    expect(transaction.merge(transaction.previous).offset, 31);
  });

  test('每个云媒体过期链接只允许刷新一次且普通错误不消耗次数', () {
    final guard = CloudLinkRefreshGuard();
    expect(guard.tryAcquire(Exception('decode failed')), isFalse);
    expect(guard.tryAcquire(const CloudPlaybackHttpException(403)), isTrue);
    expect(guard.tryAcquire(const CloudPlaybackHttpException(403)), isFalse);
    guard.reset();
    expect(guard.tryAcquire('Failed to open https://cdn.example.com'), isTrue);
    expect(guard.tryAcquire('Failed to open https://cdn.example.com'), isFalse);
  });

  test('生产媒体库注入云播放回调且不再显示服务不可用', () {
    final page = File('lib/pages/local/local_page.dart').readAsStringSync();
    final videoPage =
        File('lib/pages/video/video_page.dart').readAsStringSync();
    expect(page, contains('onPlayCloud:'));
    expect(page, contains('CloudPlaybackResolver'));
    expect(page, isNot(contains('播放服务暂不可用')));
    expect(
      page.indexOf('await _playCloudLibraryEpisode(series, episode)'),
      lessThan(page.indexOf(
          'Navigator.of(context).pop()', page.indexOf('onPlayCloud:'))),
    );
    expect(videoPage, contains('addPostFrameCallback((_) async'));
    expect(videoPage, contains('await changeEpisode('));
    expect(videoPage, contains("'VideoPage: failed to initialize playback'"));
  });
}

class _FakeClient implements CloudDriveClient {
  _FakeClient({this.resource, this.subtitle, this.error});

  final CloudPlaybackResource? resource;
  final CloudFileEntry? subtitle;
  final Object? error;
  bool closed = false;
  int authenticateCalls = 0;

  @override
  Future<void> authenticate(
      CloudSource source, CloudCredential credential) async {
    authenticateCalls++;
  }

  @override
  Future<void> close() async => closed = true;

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) async => subtitle!;

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async =>
      const [];

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) async {
    if (error != null) throw error!;
    return resource!;
  }
}
