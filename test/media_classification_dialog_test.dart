import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/features/library/presentation/media_classification_dialog.dart';
import 'package:kanyingyin/features/library/presentation/media_library_details_dialog.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  testWidgets('分类页媒体菜单打开共享分类编辑器并显示对象来源', (tester) async {
    final movie = MediaLibrarySeries(
      key: 'cloud|movie',
      seriesKey: 'movie',
      title: '同名作品',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'family',
      sourceName: '家庭媒体库',
      isAvailable: true,
      episodes: [],
      mediaType: TmdbMediaType.movie,
      genres: const ['剧情'],
      tmdbMetadata: TmdbMetadata(
        id: 1,
        mediaType: TmdbMediaType.movie,
        title: '同名作品',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 10, 11),
        matchConfidence: 1,
        genres: const ['剧情'],
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: MediaCategoryPage(
        category: MediaLibraryCategory.movie,
        initialize: () async {},
        libraryProvider: () => CloudMediaLibrary(
          series: [movie],
          filters: [MediaLibrarySourceFilter('all', '全部', null)],
        ),
        onPlayEpisode: (_, __) async {},
        onUserStateChanged: (_, __) async {},
        observeLibrary: false,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('媒体操作'));
    await tester.pumpAndSettle();

    expect(find.text('编辑分类与标签'), findsOneWidget);
    await tester.tap(find.text('编辑分类与标签'));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('media-classification-dialog'));
    expect(dialog, findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('同名作品')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('家庭媒体库')),
        findsOneWidget);
  });

  testWidgets('分类多选允许电影动漫并阻止动漫电视剧同时勾选', (tester) async {
    MediaLibraryUserState? saved;
    await _openEditor(tester, onSave: (state, _) async => saved = state);

    await tester.tap(find.byKey(const ValueKey('classification-category-电影')));
    await tester.tap(find.byKey(const ValueKey('classification-category-动漫')));
    await tester.pump();
    expect(_selected(tester, '电影'), isTrue);
    expect(_selected(tester, '动漫'), isTrue);
    await tester.tap(find.byKey(const ValueKey('classification-category-电视剧')));
    await tester.pump();
    expect(_selected(tester, '电视剧'), isTrue);
    expect(_selected(tester, '动漫'), isFalse);
    await tester.tap(find.byKey(const ValueKey('classification-category-动漫')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(saved?.categoryOverride, ['电影', '动漫']);
    expect(saved?.genreOverride, isNull);
    expect(find.byKey(const ValueKey('media-classification-dialog')),
        findsNothing);
  });

  testWidgets('题材多选和自定义标签在一次保存中提交', (tester) async {
    MediaLibraryUserState? saved;
    List<String>? tags;
    await _openEditor(tester, onSave: (state, customTags) async {
      saved = state;
      tags = customTags;
    });
    for (final genre in ['动画', '冒险']) {
      final choice = find.byKey(ValueKey('classification-genre-$genre'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pump();
    }
    final input = find.byKey(const ValueKey('classification-custom-tag-input'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '周末待看');
    await tester.tap(find.byTooltip('添加自定义标签'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(saved?.genreOverride, ['动画', '冒险']);
    expect(tags, ['周末待看']);
  });

  testWidgets('明确清空保存空列表而不是恢复自动', (tester) async {
    MediaLibraryUserState? saved;
    await _openEditor(
      tester,
      state: const MediaLibraryUserState(
        categoryOverride: ['电影'],
        genreOverride: ['冒险'],
      ),
      onSave: (state, _) async => saved = state,
    );
    await tester.tap(find.text('清空分类'));
    await tester.ensureVisible(find.text('清空题材'));
    await tester.tap(find.text('清空题材'));
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(saved?.categoryOverride, isEmpty);
    expect(saved?.genreOverride, isEmpty);
  });

  testWidgets('恢复自动等待统一保存且不改变收藏', (tester) async {
    MediaLibraryUserState? saved;
    await _openEditor(
      tester,
      state: const MediaLibraryUserState(
        favorite: true,
        categoryOverride: [],
        genreOverride: ['冒险'],
      ),
      onSave: (state, _) async => saved = state,
    );
    await tester.tap(find.text('恢复自动'));
    await tester.pump();
    expect(saved, isNull);
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(saved?.categoryOverride, isNull);
    expect(saved?.genreOverride, isNull);
    expect(saved?.favorite, isTrue);
  });

  testWidgets('取消分类编辑不会写入选择', (tester) async {
    var saves = 0;
    await _openEditor(tester, onSave: (_, __) async => saves++);
    await tester.tap(find.byKey(const ValueKey('classification-category-动漫')));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(saves, 0);
    expect(find.byKey(const ValueKey('media-classification-dialog')),
        findsNothing);
  });

  testWidgets('保存失败保留选择并可重试', (tester) async {
    var saves = 0;
    await _openEditor(tester, onSave: (_, __) async {
      saves++;
      if (saves == 1) throw StateError('write failed');
    });
    await tester.tap(find.byKey(const ValueKey('classification-category-动漫')));
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('media-classification-dialog')),
        findsOneWidget);
    expect(_selected(tester, '动漫'), isTrue);
    expect(find.text('分类与标签保存失败，已保留选择，请重试。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(find.byKey(const ValueKey('media-classification-dialog')),
        findsNothing);
  });

  testWidgets('保存期间禁用重复提交和取消', (tester) async {
    final completion = Completer<void>();
    var saves = 0;
    await _openEditor(tester, onSave: (_, __) {
      saves++;
      return completion.future;
    });
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
              find.byKey(const ValueKey('classification-save')))
          .onPressed,
      isNull,
    );
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull);
    expect(saves, 1);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-classification-dialog')),
        findsNothing);
  });

  testWidgets('分类编辑在窄视口可滚动且保存按钮保持可见', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _openEditor(tester);

    expect(tester.takeException(), isNull);
    final input = find.byKey(const ValueKey('classification-custom-tag-input'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('classification-save')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('窄视口弹出键盘并保存失败时仍能保留编辑器', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await _openEditor(tester,
        onSave: (_, __) async => throw StateError('failure'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('media-classification-dialog')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('检查列表关闭后才编辑且保存后恢复来源范围与位置', (tester) async {
    final items = [
      for (var index = 0; index < 10; index++)
        MediaLibrarySeries(
          key: 'family|$index',
          seriesKey: '$index',
          title: '检查作品 $index',
          sourceKind: MediaSourceKind.cloud,
          sourceId: 'family',
          sourceName: '家庭网盘',
          isAvailable: true,
          episodes: const [],
        ),
    ];
    final states = <String, MediaLibraryUserState>{};
    final review = find.byKey(const ValueKey('media-classification-review'),
        skipOffstage: false);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showMediaClassificationReviewDialog(
            context,
            series: items,
            sourceLabel: '家庭网盘',
            userStatesProvider: () => states,
            modeProvider: () => MediaClassificationMode.conservative,
            onEdit: (series) async {
              expect(review, findsNothing);
              await showMediaClassificationDialog(
                context,
                series: series,
                state: states[series.key] ?? MediaLibraryUserState.empty,
                mode: MediaClassificationMode.conservative,
                allowCustomTags: false,
                onSave: (state, _) async => states[series.key] = state,
              );
            },
          ),
          child: const Text('开始检查'),
        ),
      )),
    ));
    await tester.tap(find.text('开始检查'));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(of: review, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('检查作品 6'), 160, scrollable: scrollable);
    final tile = find.ancestor(of: find.text('检查作品 6'), matching: find.byType(ListTile));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    final previousOffset = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.tap(find.descendant(of: tile, matching: find.byTooltip('编辑分类与标签')));
    await tester.pumpAndSettle();
    expect(review, findsNothing);
    expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('classification-category-电影')));
    await tester.tap(find.byKey(const ValueKey('classification-save')));
    await tester.pumpAndSettle();

    expect(review, findsOneWidget);
    expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('预览“家庭网盘”全部 10 部作品'), findsOneWidget);
    expect(tester.state<ScrollableState>(scrollable).position.pixels,
        closeTo(previousOffset, 0.1));
    expect(find.descendant(of: tile, matching: find.text('有效分类：电影')), findsOneWidget);
    expect(states['family|6']?.categoryOverride, ['电影']);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    expect(review, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('检查列表关闭后才显示详情且关闭详情后返回检查', (tester) async {
    const series = MediaLibrarySeries(
      key: 'family|details',
      seriesKey: 'details',
      title: '待检查详情作品',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'family',
      sourceName: '家庭网盘',
      isAvailable: true,
      episodes: [],
    );
    final review = find.byKey(const ValueKey('media-classification-review'),
        skipOffstage: false);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showMediaClassificationReviewDialog(
            context,
            series: const [series],
            sourceLabel: '家庭网盘',
            userStatesProvider: () => const {},
            modeProvider: () => MediaClassificationMode.conservative,
            onOpen: (series) async {
              expect(review, findsNothing);
              await showMediaLibraryDetailsDialog(context: context, series: series);
            },
          ),
          child: const Text('开始检查'),
        ),
      )),
    ));
    await tester.tap(find.text('开始检查'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待检查详情作品'));
    await tester.pumpAndSettle();

    expect(review, findsNothing);
    expect(find.byKey(const ValueKey('media-details-dialog')), findsOneWidget);
    expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '关闭'));
    await tester.pumpAndSettle();
    expect(review, findsOneWidget);
    expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('预览“家庭网盘”全部 1 部作品'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    expect(review, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

bool _selected(WidgetTester tester, String label) => tester
    .widget<CheckboxListTile>(
        find.byKey(ValueKey('classification-category-$label')))
    .value!;

Future<void> _openEditor(
  WidgetTester tester, {
  MediaLibraryUserState state = MediaLibraryUserState.empty,
  Future<void> Function(MediaLibraryUserState, List<String>)? onSave,
}) async {
  final movie = MediaLibrarySeries(
    key: 'family|animated-movie',
    seriesKey: 'animated-movie',
    title: '带有多个候选的动画电影',
    sourceKind: MediaSourceKind.cloud,
    sourceId: 'family',
    sourceName: '家庭共享媒体资料库',
    isAvailable: true,
    episodes: const [],
    mediaType: TmdbMediaType.movie,
    genres: const ['动画', '冒险'],
    tmdbMetadata: TmdbMetadata(
      id: 1,
      mediaType: TmdbMediaType.movie,
      title: '带有多个候选的动画电影',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 10, 11),
      matchConfidence: 1,
      genres: const ['动画', '冒险'],
    ),
  );
  await tester.pumpWidget(MaterialApp(
    home: Builder(
        builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMediaClassificationDialog(
                  context,
                  series: movie,
                  state: state,
                  mode: MediaClassificationMode.conservative,
                  onSave: onSave ?? (_, __) async {},
                ),
                child: const Text('打开编辑器'),
              ),
            )),
  ));
  await tester.tap(find.text('打开编辑器'));
  await tester.pumpAndSettle();
}
