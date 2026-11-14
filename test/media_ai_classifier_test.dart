import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_ai_classifier.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_client.dart';

void main() {
  test('同一身份的资料已更新时丢弃旧分类响应', () async {
    final repository = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage());
    final gate = Completer<TmdbVisionClassification?>();
    final client = _Client(gate: gate);
    var library = _library(1);
    final pending = _service(client, repository).process(() => library);
    await client.started.future;
    library = _library(1, genres: ['剧情']);
    gate.complete(
        const TmdbVisionClassification(category: '动漫', confidence: .95));
    await pending;
    expect(await repository.get('cloud:work'), isNull);
  });

  test('自动补充模糊分类并保留身份标记，可信分类无需 AI', () async {
    final repository = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage());
    final client = _Client();
    final service = _service(client, repository);
    await service.process(() => _library(1, genres: ['剧情']));
    expect(client.calls, 0);
    await service.process(() => _library(1));
    expect(client.calls, 1);
    final state = await repository.get('cloud:work');
    expect(state?.categoryOverride, ['动漫']);
    expect(state?.aiClassificationIdentity, 'movie:1');
    expect(
        const MediaClassificationResolver()
            .resolve(_library(1).series.single, state: state)
            .isManual,
        isFalse);
  });

  test('等待期间人工分类和作品身份改变时不被旧响应覆盖', () async {
    final repository = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage());
    final gate = Completer<TmdbVisionClassification?>();
    final client = _Client(gate: gate);
    var library = _library(1);
    final pending = _service(client, repository).process(() => library);
    await client.started.future;
    await repository.saveClassification('cloud:work',
        categories: ['电影'], genres: null, mediaIds: []);
    library = _library(2);
    gate.complete(
        const TmdbVisionClassification(category: '动漫', confidence: .95));
    await pending;
    expect((await repository.get('cloud:work'))?.categoryOverride, ['电影']);
    expect((await repository.get('cloud:work'))?.aiClassified, isFalse);
  });

  test('全手动模式不请求分类服务', () async {
    final client = _Client();
    await _service(
            client,
            MediaLibraryUserStateRepository(
                storage: MemoryMediaLibraryUserStateStorage()),
            mode: MediaClassificationMode.manual)
        .process(() => _library(1));
    expect(client.calls, 0);
  });
}

MediaAiClassifier _service(
        _Client client, MediaLibraryUserStateRepository repository,
        {MediaClassificationMode mode =
            MediaClassificationMode.conservative}) =>
    MediaAiClassifier(
      config: () => const TmdbVisionModelConfig(
          enabled: false,
          autoClassification: true,
          baseUrl: 'https://example.com/v1',
          model: 'test'),
      mode: () => mode,
      readKey: () async => 'test',
      client: client,
      repository: repository,
    );

CloudMediaLibrary _library(int id, {List<String> genres = const ['动画']}) =>
    CloudMediaLibrary(
      filters: [],
      series: [
        MediaLibrarySeries(
            key: 'cloud:work',
            seriesKey: 'work',
            title: '作品',
            sourceKind: MediaSourceKind.cloud,
            sourceId: 'source',
            sourceName: '网盘',
            isAvailable: true,
            episodes: [],
            mediaType: TmdbMediaType.movie,
            tmdbMetadata: TmdbMetadata(
                id: id,
                mediaType: TmdbMediaType.movie,
                title: '作品',
                language: 'zh-CN',
                matchedAt: DateTime(2026),
                matchConfidence: 1,
                genres: genres))
      ],
    );

class _Client extends TmdbVisionModelClient {
  _Client({this.gate});
  final Completer<TmdbVisionClassification?>? gate;
  final started = Completer<void>();
  int calls = 0;
  @override
  Future<TmdbVisionClassification?> classify(
      {required TmdbVisionModelConfig config,
      required String apiKey,
      required String title,
      required TmdbMediaType mediaType,
      String? overview,
      Iterable<String> genres = const [],
      List<Uint8List> frames = const []}) async {
    calls++;
    if (!started.isCompleted) started.complete();
    return gate?.future ??
        Future.value(
            const TmdbVisionClassification(category: '动漫', confidence: .95));
  }
}
