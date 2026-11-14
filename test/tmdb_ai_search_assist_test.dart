import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_ai_search_assist.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_client.dart';

void main() {
  const config = TmdbVisionModelConfig(
      enabled: true, baseUrl: 'https://example.com/v1', model: 'test');
  const subject = TmdbScrapeSubject(
      stableKey: 'work',
      titleCandidates: ['旧显示标题'],
      sourceNames: ['原始目录', '原始片名.S01E01.mkv']);

  test('原始资料识别合并并发请求，清除配置后丢弃旧响应', () async {
    final client = _Client();
    final assist = TmdbAiSearchAssist(
        config: () => config, readKey: () async => 'test', client: client);
    final first = assist.identify(subject);
    final second = assist.identify(subject);
    await client.started.future;
    expect(client.calls, 1);
    expect(client.names, subject.sourceNames);
    assist.clearCache();
    client.result.complete(const TmdbVisionSuggestion(
        title: '正式片名', confidence: .95, mediaType: 'tv'));
    expect(await first, isNull);
    expect(await second, isNull);
    expect(await assist.identify(subject), isNotNull);
    expect(client.calls, 2);
  });

  test('安全存储读取失败给出可见错误，不发送请求', () async {
    final client = _Client();
    final assist = TmdbAiSearchAssist(
        config: () => config,
        readKey: () async => throw StateError('sensitive'),
        client: client);
    await expectLater(
        assist.identify(subject),
        throwsA(isA<TmdbVisionException>()
            .having((error) => error.message, 'message', contains('密钥读取失败'))));
    expect(client.calls, 0);
  });
}

class _Client extends TmdbVisionModelClient {
  final started = Completer<void>();
  final result = Completer<TmdbVisionSuggestion?>();
  var calls = 0;
  List<String> names = [];

  @override
  Future<TmdbVisionSuggestion?> identify({
    required TmdbVisionModelConfig config,
    required String apiKey,
    required String fileName,
    required List<Uint8List> frames,
    String? directoryName,
    String? seasonEpisodeInfo,
    List<String> sourceNames = const [],
    Map<String, Object?> existingTmdbInfo = const {},
  }) {
    calls++;
    names = sourceNames;
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}
