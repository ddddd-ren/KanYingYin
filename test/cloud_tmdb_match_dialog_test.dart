import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_tmdb_match_dialog.dart';
import 'package:kanyingyin/services/cloud/cloud_media_name_parser.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  testWidgets('显示结构化字段并在选择候选后应用匹配', (tester) async {
    CloudResourceTmdbSearchRequest? request;
    TmdbRankedCandidate? applied;
    await tester.pumpWidget(
      _DialogHost(
        onSearch: (value) async {
          request = value;
          return CloudResourceTmdbSearchOutcome(
            ranked: TmdbRankedResult(
              candidates: <TmdbRankedCandidate>[_rankedCandidate],
              shouldAutoMatch: true,
            ),
          );
        },
        onApply: (candidate, options) async {
          applied = candidate;
          return _selectionOutcome(candidate.metadata);
        },
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('cloud-tmdb-match-dialog')), findsOneWidget);
    expect(find.text('Alice in Borderland S01E01.mkv'), findsOneWidget);
    expect(find.text('第 1 季'), findsOneWidget);
    expect(find.text('第 1 集'), findsOneWidget);
    expect(find.textContaining('不会修改网盘文件'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('cloud-tmdb-search-title')),
          )
          .controller
          ?.text,
      'Alice in Borderland',
    );

    await tester.tap(find.widgetWithText(FilledButton, '搜索 TMDB'));
    await tester.pumpAndSettle();
    expect(request?.queryTitle, 'Alice in Borderland');
    expect(request?.queryYear, 2020);
    expect(request?.mediaTypeMode, TmdbMediaTypeMode.tv);
    expect(find.text('弥留之国的爱丽丝'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '应用匹配'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('弥留之国的爱丽丝'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '应用匹配'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, '应用匹配'));
    await tester.pumpAndSettle();

    expect(applied?.metadata.id, 42);
    expect(find.byKey(const ValueKey('cloud-tmdb-match-dialog')), findsNothing);
  });

  testWidgets('空搜索词显示验证错误且不请求 TMDB', (tester) async {
    var searchCalls = 0;
    await tester.pumpWidget(
      _DialogHost(
        onSearch: (request) async {
          searchCalls++;
          return const CloudResourceTmdbSearchOutcome(
            ranked: TmdbRankedResult(
              candidates: <TmdbRankedCandidate>[],
              shouldAutoMatch: false,
            ),
          );
        },
        onApply: (candidate, options) async =>
            _selectionOutcome(candidate.metadata),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('cloud-tmdb-search-title')),
      '   ',
    );
    await tester.tap(find.widgetWithText(FilledButton, '搜索 TMDB'));
    await tester.pump();

    expect(find.text('请输入搜索词'), findsOneWidget);
    expect(searchCalls, 0);
  });

  testWidgets('窄窗口使用上下布局', (tester) async {
    tester.view.physicalSize = const Size(650, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _DialogHost(
        onSearch: (request) async => const CloudResourceTmdbSearchOutcome(
          ranked: TmdbRankedResult(
            candidates: <TmdbRankedCandidate>[],
            shouldAutoMatch: false,
          ),
        ),
        onApply: (candidate, options) async =>
            _selectionOutcome(candidate.metadata),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cloud-tmdb-stacked')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloud-tmdb-two-column')), findsNothing);
  });
}

class _DialogHost extends StatelessWidget {
  const _DialogHost({required this.onSearch, required this.onApply});

  final CloudTmdbSearchCallback onSearch;
  final CloudTmdbApplyCallback onApply;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showDialog<CloudResourceTmdbSelectionOutcome>(
                context: context,
                builder: (context) => CloudTmdbMatchDialog(
                  title: '重新匹配 TMDB',
                  draft: const TmdbMatchDraft(
                    originalName: 'Alice in Borderland S01E01.mkv',
                    searchTitle: 'Alice in Borderland',
                    mediaTypeMode: TmdbMediaTypeMode.tv,
                    year: 2020,
                    seasonNumber: 1,
                    episodeNumber: 1,
                  ),
                  initialOptions: const TmdbScrapeOptions.defaults(),
                  onSearch: onSearch,
                  onApply: onApply,
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
  }
}

final _metadata = TmdbMetadata(
  id: 42,
  mediaType: TmdbMediaType.tv,
  title: '弥留之国的爱丽丝',
  originalTitle: 'Alice in Borderland',
  releaseDate: '2020-12-10',
  rating: 8.2,
  language: 'zh-CN',
  matchedAt: DateTime.utc(2026, 7, 19),
  matchConfidence: 1,
);

final _rankedCandidate = TmdbRankedCandidate(
  metadata: _metadata,
  score: 1,
  titleMatched: true,
  yearMatched: true,
  typeMatched: true,
);

CloudResourceTmdbSelectionOutcome _selectionOutcome(TmdbMetadata metadata) {
  return CloudResourceTmdbSelectionOutcome(
    record: CloudResourceTmdbRecord.matched(
      sourceId: 'source-a',
      remoteId: 'episode-fid',
      remotePath: '/影视/Alice in Borderland S01E01.mkv',
      displayName: 'Alice in Borderland S01E01.mkv',
      resourceKind: CloudResourceKind.standaloneVideo,
      metadata: metadata,
      checkedAt: DateTime.utc(2026, 7, 19),
    ),
    posterCached: true,
    indexSynced: true,
  );
}
