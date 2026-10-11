import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';

void main() {
  testWidgets('电视剧分类排除已识别动漫', (tester) async {
    final anime = _series(
      key: 'local|anime',
      title: '已识别动漫',
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      mediaType: TmdbMediaType.tv,
      genres: const ['动画'],
    );
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.tvSeries,
        initialize: () async {},
        libraryProvider: () => CloudMediaLibrary(
          series: [anime],
          filters: const [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        onPlayEpisode: (_, __) async {},
        observeLibrary: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ImmersiveMediaCard), findsNothing);
  });

  testWidgets('检查分类预览当前来源完整库且不会自动保存', (tester) async {
    final movie = _series(
      key: 'local|movie',
      title: '电影作品',
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      mediaType: TmdbMediaType.movie,
    );
    const unknown = MediaLibrarySeries(
      key: 'local|unknown',
      seriesKey: 'unknown',
      title: '未识别作品',
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      isAvailable: true,
      episodes: [],
    );
    var saves = 0;
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.movie,
        initialize: () async {},
        libraryProvider: () => CloudMediaLibrary(
          series: [movie, unknown],
          filters: const [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        onPlayEpisode: (_, __) async {},
        observeLibrary: false,
        onUserStateChanged: (_, __) async => saves++,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('检查分类'), findsOneWidget);
    await tester.tap(find.byTooltip('检查分类'));
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('media-classification-review'));
    expect(find.descendant(of: preview, matching: find.text('电影作品')), findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('未识别作品')), findsOneWidget);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类门槛通过持久化回调保存后才切换', (tester) async {
    var mode = MediaClassificationMode.conservative;
    final saved = <MediaClassificationMode>[];
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.movie,
        initialize: () async {},
        libraryProvider: () => const CloudMediaLibrary(
          series: [],
          filters: [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        onPlayEpisode: (_, __) async {},
        observeLibrary: false,
        classificationModeProvider: () => mode,
        onClassificationModeChanged: (value) async {
          saved.add(value);
          mode = value;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('media-classification-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标准'));
    await tester.pumpAndSettle();

    expect(saved, [MediaClassificationMode.standard]);
    expect(find.text('分类门槛：标准'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('待确认筛选跨出当前分类并仍可进入详情播放', (tester) async {
    final unknown = MediaLibrarySeries(
      key: 'cloud|unknown',
      seriesKey: 'unknown',
      title: '尚未识别的作品',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'cloud',
      sourceName: '网盘',
      isAvailable: true,
      episodes: [
        MediaLibraryEpisode.cloud(
          stableId: 'unknown-episode',
          name: '来源视频.mkv',
          sourceId: 'cloud',
          sourceName: '网盘',
          isAvailable: true,
          remoteId: 'unknown-episode',
          remotePath: '/来源视频.mkv',
        ),
      ],
    );
    MediaLibrarySeries? played;
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.movie,
        initialize: () async {},
        libraryProvider: () => CloudMediaLibrary(
          series: [unknown],
          filters: const [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        onPlayEpisode: (series, _) async => played = series,
        observeLibrary: false,
        capabilities: AppPlatformCapabilities.android,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '待确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ImmersiveMediaCard));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-details-dialog')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '播放'));
    await tester.pumpAndSettle();

    expect(played, same(unknown));
    expect(tester.takeException(), isNull);
  });

  testWidgets('待确认搜索无匹配显示筛选空态并能清除搜索', (tester) async {
    const unknown = MediaLibrarySeries(
      key: 'cloud|pending-search',
      seriesKey: 'pending-search',
      title: '仍需确认的作品',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'cloud',
      sourceName: '家庭网盘',
      isAvailable: true,
      episodes: [],
    );
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.movie,
        initialize: () async {},
        libraryProvider: () => const CloudMediaLibrary(
          series: [unknown],
          filters: [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        onPlayEpisode: (_, __) async {},
        observeLibrary: false,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '待确认'));
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    final search = find.byKey(const ValueKey('media-category-search'));
    await tester.enterText(search, '不存在的标题');
    await tester.pumpAndSettle();

    expect(find.text('暂无待确认作品'), findsNothing);
    expect(find.text('没有匹配的作品'), findsOneWidget);
    expect(find.textContaining('符合搜索的待确认作品'), findsOneWidget);
    expect(find.textContaining('全部待确认作品'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '清除搜索'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller?.text, isEmpty);
    expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    expect(find.textContaining('全部待确认作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类保存不覆盖编辑期间更新的收藏状态', (tester) async {
    final movie = _series(
      key: 'local|concurrent',
      title: '并行状态作品',
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      mediaType: TmdbMediaType.movie,
    );
    final states = <String, MediaLibraryUserState>{};
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.movie,
        initialize: () async {},
        libraryProvider: () => CloudMediaLibrary(
          series: [movie],
          filters: const [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        onPlayEpisode: (_, __) async {},
        observeLibrary: false,
        userStatesProvider: () => states,
        onUserStateChanged: (key, state) async => states[key] = state,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('媒体操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑分类与标签'));
    await tester.pumpAndSettle();
    states[movie.key] = const MediaLibraryUserState(favorite: true);
    await tester.tap(find.byKey(const ValueKey('classification-category-动漫')));
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(states[movie.key]?.favorite, isTrue);
    expect(states[movie.key]?.categoryOverride, ['电影', '动漫']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分类编辑优先使用独立原子保存回调', (tester) async {
    final movie = _series(
      key: 'local|classification',
      title: '独立分类保存作品',
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      mediaType: TmdbMediaType.movie,
    );
    var userStateSaves = 0;
    var classificationSaves = 0;
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.movie,
        initialize: () async {},
        libraryProvider: () => CloudMediaLibrary(
          series: [movie],
          filters: const [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        onPlayEpisode: (_, __) async {},
        observeLibrary: false,
        onUserStateChanged: (_, __) async => userStateSaves++,
        onClassificationChanged: (_, __) async => classificationSaves++,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('媒体操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑分类与标签'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(classificationSaves, 1);
    expect(userStateSaves, 0);
    expect(tester.takeException(), isNull);
  });

  for (final (title, season) in const [
    ('光阴之外', 1),
    ('光阴之外 第 2 季', 2),
  ]) {
    testWidgets('动漫分类悬停浮层原样显示来源剧名：$title', (tester) async {
      final series = _series(
        key: 'quark|source-title',
        title: title,
        sourceKind: MediaSourceKind.cloud,
        sourceId: 'quark',
        sourceName: '夸克网盘',
        mediaType: TmdbMediaType.tv,
        genres: const ['动画'],
        seasonNumber: season,
      );
      await tester.pumpWidget(MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.anime,
          initialize: () async {},
          libraryProvider: () => CloudMediaLibrary(
            series: [series],
            filters: const [MediaLibrarySourceFilter('all', '全部', null)],
          ),
          onPlayEpisode: (_, __) async {},
          observeLibrary: false,
          capabilities: AppPlatformCapabilities.windows,
        ),
      ));
      await tester.pumpAndSettle();

      final card = find.byType(ImmersiveMediaCard);
      final overlay = find.descendant(
        of: card,
        matching: find.byType(AnimatedOpacity),
      );
      expect(tester.widget<AnimatedOpacity>(overlay).opacity, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(card));
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedOpacity>(overlay).opacity, 1);
      expect(tester.widget<ImmersiveMediaCard>(card).title, title);
      expect(
        find.descendant(of: overlay, matching: find.text(title)),
        findsOneWidget,
      );
      expect(find.text('$title S0$season'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('详情打开期间来源改名后立即显示新名且播放使用当前作品', (tester) async {
    final notifier = ChangeNotifier();
    addTearDown(notifier.dispose);
    MediaLibrarySeries current = _series(
      key: 'source|details-refresh',
      title: '旧来源剧名',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'source',
      sourceName: '来源',
      mediaType: TmdbMediaType.movie,
    );
    MediaLibrarySeries? played;
    var sourceExists = true;
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.movie,
        initialize: () async {},
        libraryProvider: () => CloudMediaLibrary(
          series: sourceExists ? [current] : [],
          filters: const [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        libraryListenable: notifier,
        onPlayEpisode: (series, _) async => played = series,
        observeLibrary: false,
        capabilities: AppPlatformCapabilities.android,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ImmersiveMediaCard));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey<String>('media-details-dialog'));
    expect(find.descendant(of: dialog, matching: find.text('旧来源剧名')), findsOneWidget);

    current = _series(
      key: 'source|details-refresh',
      title: '光阴之外',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'source',
      sourceName: '来源',
      mediaType: TmdbMediaType.movie,
    );
    notifier.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.descendant(of: dialog, matching: find.text('光阴之外')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('旧来源剧名')), findsNothing);
    sourceExists = false;
    notifier.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.descendant(of: dialog, matching: find.text('光阴之外')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '播放'));
    await tester.pumpAndSettle();
    expect(played, same(current));
    expect(tester.takeException(), isNull);
  });

  testWidgets('选集打开期间继承新剧名单集名并保留所选版本', (tester) async {
    final notifier = ChangeNotifier();
    addTearDown(notifier.dispose);
    MediaLibrarySeries series(String title, {bool reverseVersions = false}) {
      final episodes = [
        for (final version in ['a', 'b'])
          MediaLibraryEpisode.cloud(
            stableId: 'episode-$version',
            name: '$title 来源版本 $version',
            sourceId: 'source',
            sourceName: '来源',
            isAvailable: true,
            remoteId: 'episode-$version',
            remotePath: '/work/$version.mkv',
            playbackVersionKey: version,
          ),
      ];
      final versions = [
        for (var index = 0; index < episodes.length; index++)
          MediaLibraryVersionGroup(
            key: ['a', 'b'][index],
            label: ['版本 A', '版本 B'][index],
            episodes: [episodes[index]],
          ),
      ];
      return MediaLibrarySeries(
        key: 'work',
        seriesKey: 'work',
        title: title,
        sourceKind: MediaSourceKind.cloud,
        sourceId: 'source',
        sourceName: '来源',
        isAvailable: true,
        mediaType: TmdbMediaType.tv,
        genres: const ['剧情'],
        tmdbMetadata: TmdbMetadata(
          id: 77,
          mediaType: TmdbMediaType.tv,
          title: title,
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 10, 11),
          matchConfidence: 1,
          genres: const ['剧情'],
        ),
        episodes: episodes,
        versions: reverseVersions ? versions.reversed.toList() : versions,
      );
    }

    var current = series('旧来源剧名');
    var sourceExists = true;
    MediaLibrarySeries? playedSeries;
    MediaLibraryEpisode? playedEpisode;
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.tvSeries,
        initialize: () async {},
        libraryProvider: () => CloudMediaLibrary(
          series: sourceExists ? [current] : [],
          filters: const [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        libraryListenable: notifier,
        onPlayEpisode: (series, episode) async {
          playedSeries = series;
          playedEpisode = episode;
        },
        observeLibrary: false,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ImmersiveMediaCard));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '版本 B'));
    await tester.pumpAndSettle();
    expect(find.text('旧来源剧名 来源版本 b'), findsOneWidget);

    current = series('光阴之外', reverseVersions: true);
    notifier.notifyListeners();
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey<String>('media-category-episode-focus-group'));
    expect(find.descendant(of: sheet, matching: find.text('光阴之外')), findsOneWidget);
    expect(find.text('光阴之外 来源版本 b'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '版本 B')).selected, isTrue);
    sourceExists = false;
    notifier.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('光阴之外 来源版本 b'), findsOneWidget);
    await tester.tap(find.text('光阴之外 来源版本 b'));
    await tester.pumpAndSettle();
    expect(playedSeries, same(current));
    expect(playedEpisode, same(current.versions.first.episodes.single));
    expect(tester.takeException(), isNull);
  });

  testWidgets('手动已看保存后筛选和卡片进度同步刷新', (tester) async {
    final movie = _series(
        key: 'local|done',
        title: '待看电影',
        sourceKind: MediaSourceKind.local,
        sourceId: 'local',
        sourceName: '本地',
        mediaType: TmdbMediaType.movie);
    final states = <String, MediaWatchState>{};
    await tester.pumpWidget(MaterialApp(
        home: MediaCategoryPage(
      category: MediaLibraryCategory.movie,
      initialize: () async {},
      libraryProvider: () => CloudMediaLibrary(
          series: [movie],
          filters: const [MediaLibrarySourceFilter('all', '全部', null)]),
      onPlayEpisode: (_, __) async {},
      observeLibrary: false,
      watchStatesProvider: () => states,
      onWatchedChanged: (episodes, watched) async {
        for (final e in episodes) {
          states[mediaWatchKeyForEpisode(e)] = MediaWatchState(
              watched: watched,
              position: Duration.zero,
              duration: Duration.zero,
              updatedAt: DateTime.now());
        }
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('媒体操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标记已看'));
    await tester.pumpAndSettle();
    expect(states.values.single.watched, isTrue);
    expect(
        tester
            .widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard))
            .watchProgress,
        1);
    await tester.tap(find.text('未看'));
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('待关联记录使用完整媒体库候选而非当前分类', (tester) async {
    final target = _series(
        key: 'local|tv',
        title: '目标电视剧',
        sourceKind: MediaSourceKind.local,
        sourceId: 'local',
        sourceName: '本地',
        mediaType: TmdbMediaType.tv);
    final states = {'local|旧电影': const MediaLibraryUserState(favorite: true)};
    final linked = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: MediaCategoryPage(
      category: MediaLibraryCategory.movie,
      initialize: () async {},
      libraryProvider: () => CloudMediaLibrary(
          series: [target],
          filters: const [MediaLibrarySourceFilter('all', '全部', null)]),
      onPlayEpisode: (_, __) async {},
      observeLibrary: false,
      userStatesProvider: () => states,
      onRelinkUserState: (old, target) async {
        linked.addAll([old, target]);
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 项收藏/待看记录待关联'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('local|旧电影'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('目标电视剧 · 本地'));
    await tester.pumpAndSettle();
    expect(linked, ['local|旧电影', 'local|tv']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('云媒体库快照通知后分类页立即刷新', (tester) async {
    final notifier = ChangeNotifier();
    addTearDown(notifier.dispose);
    final cloudMovie = _series(
      key: 'cloud|refresh',
      title: '待刷新电影',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '夸克网盘',
      mediaType: TmdbMediaType.movie,
    );
    var currentLibrary = CloudMediaLibrary(
      series: <MediaLibrarySeries>[cloudMovie],
      filters: const <MediaLibrarySourceFilter>[
        MediaLibrarySourceFilter('all', '全部', null),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.movie,
          initialize: () async {},
          libraryProvider: () => currentLibrary,
          libraryListenable: notifier,
          onPlayEpisode: (_, __) async {},
          observeLibrary: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('待刷新电影'), findsOneWidget);

    currentLibrary = const CloudMediaLibrary(
      series: <MediaLibrarySeries>[],
      filters: <MediaLibrarySourceFilter>[
        MediaLibrarySourceFilter('all', '全部', null),
      ],
    );
    notifier.notifyListeners();
    await tester.pump();

    expect(find.text('待刷新电影'), findsNothing);
  });

  testWidgets('分类页仅网盘资源使用统一海报组件', (tester) async {
    final local = _series(
      key: 'local|tv',
      title: '本地电视剧',
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      mediaType: TmdbMediaType.tv,
      posterUrl: '/local.jpg',
    );
    final cloud = _series(
      key: 'cloud|tv',
      title: '网盘电视剧',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'cloud',
      sourceName: '网盘',
      mediaType: TmdbMediaType.tv,
      posterCachePath: r'C:\cache\cloud.jpg',
      posterUrl: '/cloud.jpg',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.tvSeries,
          initialize: () async {},
          libraryProvider: () => CloudMediaLibrary(
            series: <MediaLibrarySeries>[local, cloud],
            filters: const <MediaLibrarySourceFilter>[
              MediaLibrarySourceFilter('all', '全部', null),
            ],
          ),
          onPlayEpisode: (_, __) async {},
          observeLibrary: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('media-category-card-cloud|tv'),
        ),
        matching: find.byType(CloudPosterImage),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('media-category-card-local|tv'),
        ),
        matching: find.byType(CloudPosterImage),
      ),
      findsNothing,
    );
  });

  testWidgets('电影入口只显示电影并可按来源筛选和打开', (tester) async {
    final localMovie = _series(
      key: 'local|movie',
      title: '本地电影',
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      mediaType: TmdbMediaType.movie,
    );
    final cloudMovie = _series(
      key: 'quark|movie',
      title: '网盘电影',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '夸克网盘',
      mediaType: TmdbMediaType.movie,
    );
    final tv = _series(
      key: 'quark|tv',
      title: '网盘电视剧',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '夸克网盘',
      mediaType: TmdbMediaType.tv,
    );
    MediaLibraryEpisode? played;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.movie,
          initialize: () async {},
          libraryProvider: () => CloudMediaLibrary(
            series: <MediaLibrarySeries>[localMovie, cloudMovie, tv],
            filters: const <MediaLibrarySourceFilter>[
              MediaLibrarySourceFilter('all', '全部', null),
              MediaLibrarySourceFilter(
                'local',
                '本地',
                MediaSourceKind.local,
              ),
              MediaLibrarySourceFilter(
                'quark',
                '夸克网盘',
                MediaSourceKind.cloud,
              ),
            ],
          ),
          onPlayEpisode: (series, episode) async => played = episode,
          observeLibrary: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('media-category-title')),
      findsOneWidget,
    );
    expect(find.text('本地电影'), findsOneWidget);
    expect(find.text('网盘电影'), findsOneWidget);
    expect(find.text('网盘电视剧'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('media-category-source-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('夸克网盘').last);
    await tester.pumpAndSettle();

    expect(find.text('本地电影'), findsNothing);
    expect(find.text('网盘电影'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('media-category-card-quark|movie'),
      ),
    );
    await tester.pumpAndSettle();
    expect(played?.stableId, cloudMovie.episodes.single.stableId);
  });

  testWidgets('窄屏下较长的网盘来源名称不会挤出分类页头部', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final cloudMovie = _series(
      key: 'quark|movie',
      title: '网盘电影',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '家庭共享夸克网盘媒体资料库',
      mediaType: TmdbMediaType.movie,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.movie,
          initialize: () async {},
          libraryProvider: () => CloudMediaLibrary(
            series: <MediaLibrarySeries>[cloudMovie],
            filters: const <MediaLibrarySourceFilter>[
              MediaLibrarySourceFilter('all', '全部', null),
              MediaLibrarySourceFilter(
                'quark',
                '家庭共享夸克网盘媒体资料库',
                MediaSourceKind.cloud,
              ),
            ],
          ),
          onPlayEpisode: (_, __) async {},
          observeLibrary: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('media-category-source-filter')),
      findsOneWidget,
    );
  });

  for (final category in MediaLibraryCategory.values) {
    testWidgets('${category.label}入口的每张海报都显示媒体操作菜单', (tester) async {
      final mediaType = category == MediaLibraryCategory.movie
          ? TmdbMediaType.movie
          : TmdbMediaType.tv;
      final genres = category == MediaLibraryCategory.anime
          ? const <String>['动画']
          : const <String>['剧情'];
      final item = _series(
        key: 'local|${category.name}',
        title: '${category.label}测试资源',
        sourceKind: MediaSourceKind.local,
        sourceId: 'local',
        sourceName: '本地',
        mediaType: mediaType,
        genres: genres,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaCategoryPage(
            category: category,
            initialize: () async {},
            libraryProvider: () => CloudMediaLibrary(
              series: <MediaLibrarySeries>[item],
              filters: const <MediaLibrarySourceFilter>[
                MediaLibrarySourceFilter('all', '全部', null),
                MediaLibrarySourceFilter(
                  'local',
                  '本地',
                  MediaSourceKind.local,
                ),
              ],
            ),
            onPlayEpisode: (_, __) async {},
            observeLibrary: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('媒体操作'), findsOneWidget);
      await tester.tap(find.byTooltip('媒体操作'));
      await tester.pumpAndSettle();
      expect(find.text('媒体详情'), findsOneWidget);
      await tester.tap(find.text('媒体详情'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('media-details-dialog')),
        findsOneWidget,
      );
      expect(
        find.text('C:\\Media\\${category.label}测试资源.mkv'),
        findsOneWidget,
      );
    });
  }

  testWidgets('网盘分类的媒体详情显示来源和远程路径', (tester) async {
    final cloudMovie = _series(
      key: 'quark|details',
      title: '网盘详情电影',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '夸克网盘',
      mediaType: TmdbMediaType.movie,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.movie,
          initialize: () async {},
          libraryProvider: () => CloudMediaLibrary(
            series: <MediaLibrarySeries>[cloudMovie],
            filters: const <MediaLibrarySourceFilter>[
              MediaLibrarySourceFilter('all', '全部', null),
              MediaLibrarySourceFilter(
                'quark',
                '夸克网盘',
                MediaSourceKind.cloud,
              ),
            ],
          ),
          onPlayEpisode: (_, __) async {},
          observeLibrary: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('媒体操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('媒体详情'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('media-details-dialog')),
        matching: find.text('夸克网盘'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('media-details-dialog')),
        matching: find.text('/网盘详情电影.mkv'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Android 手机海报默认隐藏信息浮窗并先打开详情', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final cloudMovie = _series(
      key: 'quark|android-details',
      title: '安卓详情电影',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '夸克网盘',
      mediaType: TmdbMediaType.movie,
      releaseTags: const MediaReleaseTags(
        resolution: '2160p',
        source: 'Netflix',
        codec: 'H265',
      ),
    );
    var played = false;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.movie,
          initialize: () async {},
          libraryProvider: () => CloudMediaLibrary(
            series: <MediaLibrarySeries>[cloudMovie],
            filters: const <MediaLibrarySourceFilter>[
              MediaLibrarySourceFilter('all', '全部', null),
            ],
          ),
          capabilities: AppPlatformCapabilities.android,
          onPlayEpisode: (_, __) async => played = true,
          observeLibrary: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard))
          .overlayMode,
      ImmersiveMediaCardOverlayMode.hover,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byType(ImmersiveMediaCard),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      0,
    );
    expect(find.text('夸克网盘'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ImmersiveMediaCard),
        matching: find.byType(GlassSurface),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('media-category-card-quark|android-details'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('media-details-dialog')),
      findsOneWidget,
    );
    expect(find.text('媒体详情'), findsOneWidget);
    final detailsDialog = find.byKey(
      const ValueKey<String>('media-details-dialog'),
    );
    expect(
      find.descendant(of: detailsDialog, matching: find.text('4K')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detailsDialog, matching: find.text('Netflix')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detailsDialog, matching: find.text('H265')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, '播放'));
    await tester.pumpAndSettle();
    expect(played, isTrue);
  });

  testWidgets('网盘分类菜单隐藏视频后立即移除海报', (tester) async {
    final cloudMovie = _series(
      key: 'quark|hidden-movie',
      title: '待隐藏网盘电影',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '夸克网盘',
      mediaType: TmdbMediaType.movie,
    );
    var currentLibrary = CloudMediaLibrary(
      series: <MediaLibrarySeries>[cloudMovie],
      filters: const <MediaLibrarySourceFilter>[
        MediaLibrarySourceFilter('all', '全部', null),
        MediaLibrarySourceFilter('quark', '夸克网盘', MediaSourceKind.cloud),
      ],
    );
    List<MediaLibraryEpisode>? hiddenEpisodes;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.movie,
          initialize: () async {},
          libraryProvider: () => currentLibrary,
          onPlayEpisode: (_, __) async {},
          onHideEpisodes: (series, episodes) async {
            hiddenEpisodes = episodes;
            currentLibrary = CloudMediaLibrary(
              series: const <MediaLibrarySeries>[],
              filters: currentLibrary.filters,
            );
          },
          observeLibrary: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('媒体操作'));
    await tester.pumpAndSettle();
    expect(find.text('隐藏视频'), findsOneWidget);
    await tester.tap(find.text('隐藏视频'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '隐藏'));
    await tester.pumpAndSettle();

    expect(hiddenEpisodes, isNotNull);
    expect(hiddenEpisodes, hasLength(1));
    expect(find.text('待隐藏网盘电影'), findsNothing);
  });
}

MediaLibrarySeries _series({
  required String key,
  required String title,
  required MediaSourceKind sourceKind,
  required String sourceId,
  required String sourceName,
  required TmdbMediaType mediaType,
  List<String> genres = const <String>['剧情'],
  String? posterCachePath,
  String? posterUrl,
  int? seasonNumber,
  MediaReleaseTags releaseTags = const MediaReleaseTags(),
}) {
  final episode = sourceKind == MediaSourceKind.local
      ? MediaLibraryEpisode.local(
          stableId: key,
          name: '$title.mkv',
          localItem: LocalMediaIndexItem(
            path: 'C:\\Media\\$title.mkv',
            name: '$title.mkv',
            parentPath: r'C:\Media',
            sourcePath: r'C:\Media',
            size: 10,
            modified: DateTime.utc(2026, 8, 5),
            seriesName: title,
            seasonNumber: seasonNumber,
            indexedAt: DateTime.utc(2026, 8, 5),
            tmdb: TmdbMetadata(
              id: key.hashCode,
              mediaType: mediaType,
              title: title,
              language: 'zh-CN',
              matchedAt: DateTime.utc(2026, 8, 5),
              matchConfidence: 1,
              genres: genres,
            ),
          ),
        )
      : MediaLibraryEpisode.cloud(
          stableId: '$key-episode',
          name: '$title.mkv',
          sourceId: sourceId,
          sourceName: sourceName,
          isAvailable: true,
          remoteId: '$key-episode',
          remotePath: '/$title.mkv',
          seasonNumber: seasonNumber,
          releaseTags: releaseTags,
        );
  return MediaLibrarySeries(
    key: key,
    seriesKey: title,
    title: title,
    sourceKind: sourceKind,
    sourceId: sourceId,
    sourceName: sourceName,
    isAvailable: true,
    episodes: <MediaLibraryEpisode>[episode],
    mediaType: mediaType,
    genres: genres,
    tmdbMetadata: TmdbMetadata(
      id: key.hashCode,
      mediaType: mediaType,
      title: title,
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 10, 11),
      matchConfidence: 1,
      genres: genres,
    ),
    posterCachePath: posterCachePath,
    tmdbPosterUrl: posterUrl,
  );
}
