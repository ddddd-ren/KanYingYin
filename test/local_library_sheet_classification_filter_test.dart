import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/library_sheet.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/repositories/local_media_tag_repository.dart';
import 'package:mobx/mobx.dart';

void main() {
  testWidgets('本地抽屉分类筛选不接受同名自定义标签', (tester) async {
    await _showLibrary(tester);
    await _openFilters(tester);
    await tester.tap(_filterItems('电视剧').first);
    await tester.pumpAndSettle();

    expect(find.text('真人剧作品'), findsOneWidget);
    expect(find.text('动画作品'), findsNothing);
  });

  testWidgets('本地抽屉自定义标签筛选不接受同名分类', (tester) async {
    await _showLibrary(tester);
    await _openFilters(tester);
    await tester.tap(_filterItems('电视剧').last);
    await tester.pumpAndSettle();

    expect(find.text('动画作品'), findsOneWidget);
    expect(find.text('真人剧作品'), findsNothing);
    await _openFilters(tester);
    final matching = tester
        .widgetList<CheckedPopupMenuItem<String>>(
          _filterItems('电视剧'),
        )
        .toList();
    expect(matching.first.checked, isFalse);
    expect(matching.last.checked, isTrue);
  });

  testWidgets('本地抽屉题材与同名自定义标签分别计数并按交集筛选', (tester) async {
    await _showLibrary(tester);
    await _openFilters(tester);
    await tester.tap(_filterItems('剧情').first);
    await tester.pumpAndSettle();
    expect(find.text('真人剧作品'), findsOneWidget);
    expect(find.text('动画作品'), findsNothing);

    await _openFilters(tester);
    await tester.tap(_filterItems('剧情').last);
    await tester.pumpAndSettle();
    expect(find.text('类型 2'), findsOneWidget);
    expect(find.text('没有匹配的系列'), findsOneWidget);

    await _openFilters(tester);
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('动画作品'), findsOneWidget);
    expect(find.text('真人剧作品'), findsOneWidget);
  });

  testWidgets('本地抽屉移除失效分类时不被同名自定义标签保留', (tester) async {
    final controller = await _showLibrary(tester);
    await _openFilters(tester);
    await tester.tap(_filterItems('电视剧').first);
    await tester.pumpAndSettle();

    controller.localLibraryItems
        .removeWhere((item) => item.seriesName == '真人剧作品');
    await tester.pumpAndSettle();

    expect(find.text('动画作品'), findsOneWidget);
    expect(find.text('类型'), findsOneWidget);
    expect(find.text('类型 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地抽屉标签首写落盘后失败会恢复原标签并保留筛选', (tester) async {
    final controller = LocalController();
    controller.localLibraryItems.addAll([
      _item(1, '动画作品', ['动画']),
      _item(2, '真人剧作品', ['剧情']),
    ]);
    final series = controller.localMediaLibrary.series
        .singleWhere((item) => item.title == '动画作品');
    final box = _FailingTagBox();
    final tags = LocalMediaTagRepository(box: box);
    final states = MediaLibraryUserStateRepository(
      storage: MemoryMediaLibraryUserStateStorage(),
    );
    await tags.saveForSeries(series.seriesKey, ['电视剧', '剧情']);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          tagRepository: tags,
          userStateRepository: states,
          settings: TypedSettings(_SettingsBox()),
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await _openFilters(tester);
    await tester.tap(_filterItems('电视剧').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('播放选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑分类与标签'));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('classification-custom-tag-input'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '新增标签');
    box.failAfterNextWrite = true;
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(tags.getAll()[series.seriesKey], ['电视剧', '剧情']);
    expect(await states.get(series.key), isNull);
    expect(find.text('分类与标签保存失败，已保留选择，请重试。'), findsOneWidget);
    expect(find.byKey(const ValueKey('media-classification-dialog')),
        findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('类型 1'), findsOneWidget);
    expect(find.text('动画作品'), findsOneWidget);
    expect(find.text('真人剧作品'), findsNothing);
    await _openFilters(tester);
    expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(_filterItems('电视剧').last)
            .checked,
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地抽屉剧集菜单按 TMDB 状态只显示一个匹配动作', (tester) async {
    final controller = LocalController();
    controller.localLibraryItems.add(
      _item(1, '待匹配作品', const [], matched: false),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          tagRepository: _Tags({}),
          settings: TypedSettings(_SettingsBox()),
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('播放选项'));
    await tester.pumpAndSettle();
    expect(find.text('TMDB 刮削'), findsOneWidget);
    expect(find.text('刮削信息'), findsNothing);
    expect(find.text('重新匹配'), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();

    controller.localLibraryItems[0] =
        _item(1, '待匹配作品', const [], matched: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('播放选项'));
    await tester.pumpAndSettle();
    expect(find.text('重新匹配'), findsOneWidget);
    expect(find.text('TMDB 刮削'), findsNothing);
  });

  for (final replaceList in [false, true]) {
    testWidgets('本地抽屉${replaceList ? '替换索引列表' : '修改列表项'}重分组后保留人工分类',
        (tester) async {
      final controller = LocalController();
      final original = _item(1, '动画作品', ['动画']);
      controller.localLibraryItems.add(original);
      final oldSeries = controller.localMediaLibrary.series.single;
      final repository = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage(),
      );
      await repository.save(
        oldSeries.key,
        MediaLibraryUserState(
          favorite: true,
          categoryOverride: const ['电影'],
          genreOverride: const ['自选题材'],
          mediaIds:
              oldSeries.episodes.map((episode) => episode.stableId).toList(),
        ),
      );
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: LibrarySheetContent(
        controller: controller,
        tagRepository: _Tags({}),
        userStateRepository: repository,
        settings: TypedSettings(_SettingsBox()),
        onPlay: (_, __) {},
        onRefresh: () {},
      ))));
      await tester.pumpAndSettle();
      await _openFilters(tester);
      expect(_filterItems('电影'), findsOneWidget);
      expect(_filterItems('自选题材'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      final regrouped = original.copyWith(seriesName: '重新分组', episodeNumber: 1);
      if (replaceList) {
        controller.localLibraryItems = ObservableList.of([regrouped]);
      } else {
        controller.localLibraryItems[0] = regrouped;
      }
      await tester.pumpAndSettle();
      final currentSeries = controller.localMediaLibrary.series.single;
      expect(currentSeries.key, isNot(oldSeries.key));

      final state = await repository.get(currentSeries.key);
      expect(state?.categoryOverride, ['电影']);
      expect(state?.genreOverride, ['自选题材']);
      expect(state?.favorite, isTrue);
      expect(await repository.get(oldSeries.key), isNull);
      await _openFilters(tester);
      expect(_filterItems('电影'), findsOneWidget);
      expect(_filterItems('自选题材'), findsOneWidget);
      expect(_filterItems('动漫'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<LocalController> _showLibrary(WidgetTester tester) async {
  final controller = LocalController();
  controller.localLibraryItems.addAll([
    _item(1, '动画作品', ['动画']),
    _item(2, '真人剧作品', ['剧情']),
  ]);
  final animation = controller.localMediaLibrary.series
      .singleWhere((series) => series.title == '动画作品');
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: LibrarySheetContent(
    controller: controller,
    tagRepository: _Tags({
      animation.seriesKey: ['电视剧', '剧情']
    }),
    onPlay: (_, __) {},
    onRefresh: () {},
  ))));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.byTooltip('筛选 TMDB 类型'));
  await tester.pumpAndSettle();
}

Finder _filterItems(String label) => find.byWidgetPredicate((widget) =>
    widget is CheckedPopupMenuItem<String> &&
    widget.child is Text &&
    (widget.child as Text).data == label);

LocalMediaIndexItem _item(
  int id,
  String title,
  List<String> genres, {
  bool matched = true,
}) =>
    LocalMediaIndexItem(
      path: 'C:\\Media\\$title\\$title.mkv',
      name: '$title.mkv',
      parentPath: 'C:\\Media\\$title',
      sourcePath: r'C:\Media',
      size: 1024,
      modified: DateTime.utc(2026, 10, 11),
      seriesName: title,
      indexedAt: DateTime.utc(2026, 10, 11),
      tmdb: matched
          ? TmdbMetadata(
              id: id,
              mediaType: TmdbMediaType.tv,
              title: title,
              genres: genres,
              language: 'zh-CN',
              matchedAt: DateTime.utc(2026, 10, 11),
              matchConfidence: 1,
            )
          : null,
    );

class _Tags implements ILocalMediaTagRepository {
  _Tags(this.values);

  final Map<String, List<String>> values;

  @override
  Map<String, List<String>> getAll() => values;

  @override
  Future<void> saveForSeries(String seriesKey, Iterable<String> tags) async {
    values[seriesKey] = tags.toList();
  }
}

class _SettingsBox extends Fake implements Box<Object?> {
  @override
  Object? get(Object? key, {Object? defaultValue}) => defaultValue;
}

class _FailingTagBox extends Fake implements Box<Object?> {
  Object? _value;
  bool failAfterNextWrite = false;

  @override
  Object? get(Object? key, {Object? defaultValue}) => _value ?? defaultValue;

  @override
  Future<void> put(Object? key, Object? value) async {
    _value = value;
    if (failAfterNextWrite) {
      failAfterNextWrite = false;
      throw StateError('模拟已写入后的存储失败');
    }
  }
}
