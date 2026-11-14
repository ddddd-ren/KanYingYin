import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/tmdb_match_dialog.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_client.dart';

void main() {
  testWidgets('AI 等待期间的人工输入不会被旧结果覆盖', (tester) async {
    final gate = Completer<TmdbVisionSuggestion?>();
    var searches = 0;
    await tester.pumpWidget(MaterialApp(
        home: TmdbMatchDialog<void>(
      title: 'TMDB 刮削',
      safetyText: '不会修改媒体文件',
      draft: const TmdbMatchDraft(
          originalName: '原片名',
          searchTitle: '原片名',
          mediaTypeMode: TmdbMediaTypeMode.auto),
      initialOptions: const TmdbScrapeOptions.defaults(),
      onIdentify: () => gate.future,
      onSearch: (_) async {
        searches++;
        return const TmdbPreparedSearchOutcome(
            ranked: TmdbRankedResult(candidates: [], shouldAutoMatch: false));
      },
      onApply: (_, __) async {},
    )));
    await tester.tap(find.text('AI 识别剧名'));
    await tester.pump();
    final title = find.byKey(const ValueKey('tmdb-search-title'));
    await tester.enterText(title, '人工新片名');
    gate.complete(const TmdbVisionSuggestion(title: '旧建议', confidence: .9));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(title).controller?.text, '人工新片名');
    expect(searches, 0);
  });

  testWidgets('共享对话框提供 AI 识别剧名入口并回填搜索资料', (tester) async {
    var identifyCount = 0;
    TmdbPreparedSearchRequest? request;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => TmdbMatchDialog<void>(
                title: 'TMDB 刮削',
                safetyText: '不会修改媒体文件',
                draft: const TmdbMatchDraft(
                  originalName: '未知作品',
                  searchTitle: '未知作品',
                  mediaTypeMode: TmdbMediaTypeMode.auto,
                ),
                initialOptions: const TmdbScrapeOptions.defaults(),
                onIdentify: () async {
                  identifyCount++;
                  return const TmdbVisionSuggestion(
                    title: 'AI 识别剧名',
                    year: 2020,
                    mediaType: 'tv',
                    confidence: 0.9,
                  );
                },
                onSearch: (value) async {
                  request = value;
                  return const TmdbPreparedSearchOutcome(
                    ranked: TmdbRankedResult(
                      candidates: <TmdbRankedCandidate>[],
                      shouldAutoMatch: false,
                    ),
                  );
                },
                onApply: (_, __) async {},
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 识别剧名'));
    await tester.pumpAndSettle();
    expect(identifyCount, 1);
    expect(request?.queryTitle, 'AI 识别剧名');
    expect(find.byKey(const ValueKey<String>('tmdb-search-title')),
        findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('tmdb-search-title')),
          )
          .controller
          ?.text,
      'AI 识别剧名',
    );
    expect(request?.queryTitle, 'AI 识别剧名');
    expect(request?.queryYear, 2020);
    expect(request?.mediaTypeMode, TmdbMediaTypeMode.tv);
    expect(request?.skipVisionAssist, isTrue);
  });

  testWidgets('共享对话框转发准备搜索参数并返回应用结果', (tester) async {
    TmdbPreparedSearchRequest? request;
    String? dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              dialogResult = await showDialog<String>(
                context: context,
                builder: (_) => TmdbMatchDialog<String>(
                  title: 'TMDB 刮削',
                  safetyText: '仅更新看影音资料，不会修改媒体文件',
                  draft: const TmdbMatchDraft(
                    originalName: '神探夏洛克 S02',
                    searchTitle: '神探夏洛克',
                    mediaTypeMode: TmdbMediaTypeMode.tv,
                    year: 2012,
                    seasonNumber: 2,
                  ),
                  initialOptions: const TmdbScrapeOptions.defaults(),
                  onSearch: (value) async {
                    request = value;
                    return TmdbPreparedSearchOutcome(
                      ranked: TmdbRankedResult(
                        candidates: <TmdbRankedCandidate>[_candidate],
                        shouldAutoMatch: true,
                      ),
                    );
                  },
                  onApply: (candidate, options) async =>
                      'saved:${candidate.metadata.id}',
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tmdb-match-dialog')),
        findsOneWidget);
    expect(find.text('第 2 季'), findsOneWidget);
    expect(find.text('仅更新看影音资料，不会修改媒体文件'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '搜索 TMDB'));
    await tester.pumpAndSettle();
    expect(request?.queryTitle, '神探夏洛克');
    expect(request?.queryYear, 2012);
    expect(request?.mediaTypeMode, TmdbMediaTypeMode.tv);
    final candidatePoster = find.byKey(
      const ValueKey<String>('tmdb-candidate-poster-42'),
    );
    expect(tester.getSize(candidatePoster), const Size(56, 84));

    await tester.tap(find.text('神探夏洛克').last);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '应用匹配'));
    await tester.pumpAndSettle();
    expect(dialogResult, 'saved:42');
  });

  testWidgets('共享对话框校验空搜索词和非法年份', (tester) async {
    var searchCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => TmdbMatchDialog<String>(
                title: '重新匹配 TMDB',
                safetyText: '不会修改媒体文件',
                draft: const TmdbMatchDraft(
                  originalName: '未知作品',
                  searchTitle: '',
                  mediaTypeMode: TmdbMediaTypeMode.auto,
                ),
                initialOptions: const TmdbScrapeOptions.defaults(),
                onSearch: (_) async {
                  searchCount++;
                  return const TmdbPreparedSearchOutcome(
                    ranked: TmdbRankedResult(
                      candidates: <TmdbRankedCandidate>[],
                      shouldAutoMatch: false,
                    ),
                  );
                },
                onApply: (_, __) async => 'saved',
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('tmdb-year')),
      '20',
    );
    await tester.tap(find.widgetWithText(FilledButton, '搜索 TMDB'));
    await tester.pump();

    expect(find.text('请输入搜索词'), findsOneWidget);
    expect(find.text('请输入四位年份'), findsOneWidget);
    expect(searchCount, 0);
  });

  testWidgets('共享对话框在窄窗口使用堆叠布局', (tester) async {
    tester.view.physicalSize = const Size(640, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<String>(
              context: context,
              builder: (_) => TmdbMatchDialog<String>(
                title: 'TMDB 刮削',
                safetyText: '不会修改媒体文件',
                draft: const TmdbMatchDraft(
                  originalName: '电影',
                  searchTitle: '电影',
                  mediaTypeMode: TmdbMediaTypeMode.movie,
                ),
                initialOptions: const TmdbScrapeOptions.defaults(),
                onSearch: (_) async => TmdbPreparedSearchOutcome(
                  ranked: TmdbRankedResult(
                    candidates: <TmdbRankedCandidate>[],
                    shouldAutoMatch: false,
                  ),
                ),
                onApply: (_, __) async => 'saved',
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('tmdb-stacked')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('tmdb-two-column')),
      findsNothing,
    );
  });

  testWidgets('候选卡显示匹配理由和别名信号', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => TmdbMatchDialog<void>(
                title: 'TMDB 刮削',
                safetyText: '不会修改媒体文件',
                draft: const TmdbMatchDraft(
                  originalName: '三体',
                  searchTitle: '三体',
                  mediaTypeMode: TmdbMediaTypeMode.tv,
                ),
                initialOptions: const TmdbScrapeOptions.defaults(),
                onSearch: (_) async => TmdbPreparedSearchOutcome(
                  ranked: TmdbRankedResult(
                    candidates: <TmdbRankedCandidate>[
                      _candidate.copyWithForTest(
                        aliasMatched: true,
                        matchReason: '别名匹配 · 类型匹配',
                      ),
                    ],
                    shouldAutoMatch: false,
                  ),
                ),
                onApply: (_, __) async {},
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '搜索 TMDB'));
    await tester.pumpAndSettle();
    expect(find.text('别名匹配'), findsWidgets);
    expect(find.text('别名匹配 · 类型匹配'), findsOneWidget);
  });

  testWidgets('候选理由为空时不渲染空文本', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => TmdbMatchDialog<void>(
                title: 'TMDB 刮削',
                safetyText: '不会修改媒体文件',
                draft: const TmdbMatchDraft(
                  originalName: '三体',
                  searchTitle: '三体',
                  mediaTypeMode: TmdbMediaTypeMode.tv,
                ),
                initialOptions: const TmdbScrapeOptions.defaults(),
                onSearch: (_) async => TmdbPreparedSearchOutcome(
                  ranked: TmdbRankedResult(
                    candidates: <TmdbRankedCandidate>[_candidate],
                    shouldAutoMatch: false,
                  ),
                ),
                onApply: (_, __) async {},
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '搜索 TMDB'));
    await tester.pumpAndSettle();
    expect(find.text('null'), findsNothing);
  });
}

final _candidate = TmdbRankedCandidate(
  metadata: TmdbMetadata(
    id: 42,
    mediaType: TmdbMediaType.tv,
    title: '神探夏洛克',
    releaseDate: '2012-01-01',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 7, 21),
    matchConfidence: 1,
  ),
  score: 1,
  titleMatched: true,
  yearMatched: true,
  typeMatched: true,
);

extension on TmdbRankedCandidate {
  TmdbRankedCandidate copyWithForTest({
    bool? aliasMatched,
    String? matchReason,
  }) {
    return TmdbRankedCandidate(
      metadata: metadata,
      score: score,
      titleMatched: titleMatched,
      yearMatched: yearMatched,
      typeMatched: typeMatched,
      aliasMatched: aliasMatched ?? this.aliasMatched,
      titleSimilarity: titleSimilarity,
      seasonEvidenceMatched: seasonEvidenceMatched,
      matchReason: matchReason ?? this.matchReason,
    );
  }
}
