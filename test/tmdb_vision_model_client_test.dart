import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_client.dart';

void main() {
  const configured = TmdbVisionModelConfig(
    enabled: true,
    baseUrl: 'https://llm.example.com/v1',
    model: 'vision-model',
  );

  for (final status in [401, 404, 429]) {
    test('HTTP $status 展示安全错误且不回显服务正文', () async {
      final client = TmdbVisionModelClient(
          dio: Dio()
            ..httpClientAdapter = _CaptureAdapter(
                '{"error":"secret-private-data"}',
                status: status));
      await expectLater(
          client.identify(
              config: configured,
              apiKey: 'secret-private-key',
              fileName: '影片.mkv',
              frames: []),
          throwsA(isA<TmdbVisionException>().having(
              (error) => error.message, 'message', contains('HTTP $status'))));
      expect(TmdbVisionModelClient.activity.value, isNot(contains('secret')));
    });
  }

  test('只填写服务根地址时自动补齐 v1', () {
    expect(
        const TmdbVisionModelConfig(
          enabled: true,
          baseUrl: 'https://llm.example.com/',
          model: 'model',
        ).chatCompletionsUri.toString(),
        'https://llm.example.com/v1/chat/completions');
  });

  test('只启用分类时配置仍有效', () {
    expect(
        const TmdbVisionModelConfig(
          enabled: false,
          autoClassification: true,
          baseUrl: 'https://llm.example.com/v1',
          model: 'vision-model',
        ).isConfigured,
        isTrue);
  });

  test('模型格式错误不能伪装成未识别', () async {
    final client = TmdbVisionModelClient(
      dio: Dio()
        ..httpClientAdapter = _CaptureAdapter(
          '{"choices":[{"message":{"content":"not json"}}]}',
        ),
    );
    await expectLater(
        client.identify(
          config: configured,
          apiKey: 'secret',
          fileName: 'test.mkv',
          frames: [],
        ),
        throwsA(isA<Exception>()));
  });

  test('连接诊断拒绝只有 choices 的无效响应', () async {
    final client = TmdbVisionModelClient(
      dio: Dio()..httpClientAdapter = _CaptureAdapter('{"choices":[{}]}'),
    );
    expect(await client.testConnection(config: configured, apiKey: 'secret'),
        isFalse);
  });

  test('识别兼容字符串置信度', () async {
    final client = TmdbVisionModelClient(
      dio: Dio()
        ..httpClientAdapter = _CaptureAdapter(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'title': '三体',
                    'confidence': '0.92',
                    'mediaType': 'tv',
                  })
                }
              }
            ]
          }),
        ),
    );
    final result = await client.identify(
      config: configured,
      apiKey: 'secret',
      fileName: '三体.mkv',
      frames: [],
    );
    expect(result?.title, '三体');
  });

  test('模型配置规范化自定义兼容接口地址', () {
    final config = TmdbVisionModelConfig.fromMap(<String, Object?>{
      'enabled': true,
      'baseUrl': 'https://llm.example.com/v1/',
      'model': 'vision-model',
      'autoClassification': true,
    });

    expect(config.enabled, isTrue);
    expect(config.autoClassification, isTrue);
    expect(config.chatCompletionsUri.toString(),
        'https://llm.example.com/v1/chat/completions');
    expect(
      TmdbVisionModelConfig.fromMap(<String, Object?>{
        'baseUrl': 'file:///tmp',
      }).isConfigured,
      isFalse,
    );
  });

  test('请求包含文件名和不超过三张内嵌图像并解析识别结果', () async {
    final adapter = _CaptureAdapter(
      jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'content':
                  '{"title":"正确剧名","year":2020,"mediaType":"tv","confidence":0.92}',
            },
          },
        ],
      }),
    );
    final client = TmdbVisionModelClient(
      dio: Dio()..httpClientAdapter = adapter,
    );

    final result = await client.identify(
      config: const TmdbVisionModelConfig(
        enabled: true,
        baseUrl: 'https://llm.example.com/v1',
        model: 'vision-model',
      ),
      apiKey: 'secret',
      fileName: 'mystery-video.mkv',
      frames: <Uint8List>[
        Uint8List.fromList(<int>[1, 2, 3]),
        Uint8List.fromList(<int>[4, 5, 6]),
        Uint8List.fromList(<int>[7, 8, 9]),
        Uint8List.fromList(<int>[10]),
      ],
    );

    expect(result?.title, '正确剧名');
    expect(result?.year, 2020);
    expect(result?.mediaType, 'tv');
    expect(adapter.options?.uri.path, '/v1/chat/completions');
    expect(adapter.options?.headers['Authorization'], 'Bearer secret');
    final body = adapter.options?.data as Map<String, Object?>;
    final messages = body['messages']! as List<Object?>;
    final content =
        (messages.last! as Map<String, Object?>)['content']! as List<Object?>;
    expect(
        content
            .whereType<Map<String, Object?>>()
            .where((item) => item['type'] == 'image_url'),
        hasLength(3));
  });

  test('没有可用画面时仍使用文件资料识别剧名', () async {
    final adapter = _CaptureAdapter(
      jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'content':
                  '{"title":"文字识别剧名","year":2021,"mediaType":"tv","confidence":0.9}',
            },
          },
        ],
      }),
    );
    final result = await TmdbVisionModelClient(
      dio: Dio()..httpClientAdapter = adapter,
    ).identify(
      config: const TmdbVisionModelConfig(
        enabled: true,
        baseUrl: 'https://llm.example.com/v1',
        model: 'vision-model',
      ),
      apiKey: 'secret',
      fileName: 'Show S01E02.mkv',
      frames: const <Uint8List>[],
    );

    expect(result?.title, '文字识别剧名');
    final body = adapter.options?.data as Map<String, Object?>;
    final content = ((body['messages']! as List).single as Map)['content'];
    expect(content, isA<String>());
    expect(content, contains('Show S01E02.mkv'));
  });

  test('拒绝空标题和无效年份', () async {
    final client = TmdbVisionModelClient(
      dio: Dio()
        ..httpClientAdapter = _CaptureAdapter(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{
                  'content': jsonEncode(<String, Object?>{
                    'title': ' ',
                    'year': 1800,
                    'confidence': 0.9,
                  }),
                },
              },
            ],
          }),
        ),
    );

    final result = await client.identify(
      config: const TmdbVisionModelConfig(
        enabled: true,
        baseUrl: 'https://llm.example.com/v1',
        model: 'vision-model',
      ),
      apiKey: 'secret',
      fileName: 'unknown.mkv',
      frames: <Uint8List>[
        Uint8List.fromList(<int>[1])
      ],
    );

    expect(result, isNull);
  });

  test('解析受限的 AI 主分类结果', () async {
    final adapter = _CaptureAdapter(
      jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'content': '{"category":"动漫","confidence":0.91}',
            },
          },
        ],
      }),
    );
    final result = await TmdbVisionModelClient(
      dio: Dio()..httpClientAdapter = adapter,
    ).classify(
      config: const TmdbVisionModelConfig(
        enabled: true,
        baseUrl: 'https://llm.example.com/v1',
        model: 'vision-model',
      ),
      apiKey: 'secret',
      title: '某动画',
      mediaType: TmdbMediaType.tv,
      genres: const <String>['动画'],
      frames: <Uint8List>[
        Uint8List.fromList(<int>[1])
      ],
    );

    expect(result?.category, '动漫');
    expect(result?.confidence, 0.91);
    final body = adapter.options?.data as Map<String, Object?>;
    final messages = body['messages']! as List<Object?>;
    final content =
        (messages.single as Map<String, Object?>)['content']! as List<Object?>;
    expect(
      content.whereType<Map<String, Object?>>().where(
            (item) => item['type'] == 'image_url',
          ),
      hasLength(1),
    );
  });
}

class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.responseBody, {this.status = 200});

  final String responseBody;
  final int status;
  RequestOptions? options;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    return ResponseBody.fromString(responseBody, status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}
