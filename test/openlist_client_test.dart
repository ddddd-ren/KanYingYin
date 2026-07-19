import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/openlist/openlist_client.dart';

void main() {
  group('OpenListClient', () {
    late Dio dio;
    late _RecordingInterceptor api;
    late MemoryCloudCredentialStore credentials;
    late OpenListClient client;
    const source = CloudSource(
      id: 'openlist-1',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://drive.example.com///',
      rootPaths: ['/'],
    );

    setUp(() {
      dio = Dio();
      api = _RecordingInterceptor();
      dio.interceptors.add(api);
      credentials = MemoryCloudCredentialStore();
      client = OpenListClient(
        source: source,
        credentialStore: credentials,
        dio: dio,
      );
    });

    test('登录使用规范化地址并安全保存令牌', () async {
      api.responses['/api/auth/login'] = <String, Object?>{
        'code': 200,
        'data': <String, Object?>{'token': 'secret-token'},
      };

      await client.authenticate(
        source,
        const CloudCredential(username: 'alice', password: 'secret-password'),
      );

      expect(api.requests.single.uri.toString(),
          'https://drive.example.com/api/auth/login');
      expect(api.requests.single.data, <String, Object?>{
        'username': 'alice',
        'password': 'secret-password'
      });
      expect((await credentials.read(source.id))?.token, 'secret-token');
      expect(client.toString(), isNot(contains('secret-token')));
      expect(client.toString(), isNot(contains('secret-password')));
    });

    test('已有令牌时复用令牌且不重复登录', () async {
      await credentials.write(
        source.id,
        const CloudCredential(
          username: 'alice',
          password: 'secret-password',
          token: 'secret-token',
        ),
      );

      await client.authenticate(
        source,
        const CloudCredential(
          username: 'alice',
          password: 'secret-password',
          token: 'secret-token',
        ),
      );

      expect(api.requests.where((r) => r.path == '/api/auth/login'), isEmpty);
      expect((await credentials.read(source.id))?.token, 'secret-token');
    });

    test('仅保存账号密码时首次请求先登录再访问目录', () async {
      await credentials.write(
        source.id,
        const CloudCredential(
          username: 'alice',
          password: 'secret-password',
        ),
      );
      api.responses['/api/auth/login'] = <String, Object?>{
        'code': 200,
        'data': <String, Object?>{'token': 'secret-token'},
      };
      api.pagedListResponses = <Map<String, Object?>>[
        <String, Object?>{
          'code': 200,
          'data': <String, Object?>{'content': <Object?>[], 'total': 0},
        },
      ];

      await client.listDirectory('/');

      expect(
        api.requests.where((r) => r.path == '/api/auth/login'),
        hasLength(1),
      );
      final listRequest =
          api.requests.singleWhere((r) => r.path == '/api/fs/list');
      expect(listRequest.headers['Authorization'], 'secret-token');
    });

    test('空凭据按匿名方式列目录、取文件并解析播放地址', () async {
      api.pagedListResponses = <Map<String, Object?>>[
        <String, Object?>{
          'code': 200,
          'data': <String, Object?>{'content': <Object?>[], 'total': 0},
        },
      ];
      api.responses['/api/fs/get'] = <String, Object?>{
        'code': 200,
        'data': <String, Object?>{
          'name': '示例.mp4',
          'size': 1234,
          'modified': '2026-07-15T11:00:00Z',
          'is_dir': false,
          'raw_url': 'https://cdn.example.com/video',
        },
      };

      await client.authenticate(source, const CloudCredential());
      await client.listDirectory('/');
      await client.getFile('/示例.mp4');
      await client.resolvePlayback('/示例.mp4');

      expect(api.requests.where((r) => r.path == '/api/auth/login'), isEmpty);
      for (final request in api.requests) {
        expect(request.headers.containsKey('Authorization'), isFalse);
      }
    });

    test('匿名请求返回 401 时直接失败且不循环登录', () async {
      api.responseQueues['/api/fs/list'] = <Map<String, Object?>>[
        <String, Object?>{'code': 401},
      ];

      await expectLater(
        client.listDirectory('/'),
        throwsA(isA<CloudDriveException>().having(
          (e) => e.type,
          '类型',
          CloudDriveErrorType.authentication,
        )),
      );

      expect(api.requests.where((r) => r.path == '/api/fs/list'), hasLength(1));
      expect(api.requests.where((r) => r.path == '/api/auth/login'), isEmpty);
    });

    test('目录列表携带认证和分页参数并解析全部页面', () async {
      await credentials.write(
        source.id,
        const CloudCredential(token: 'secret-token'),
      );
      api.pagedListResponses = <Map<String, Object?>>[
        <String, Object?>{
          'code': 200,
          'data': <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'name': '电影',
                'size': 0,
                'modified': '2026-07-15T10:00:00Z',
                'is_dir': true,
              },
            ],
            'total': 2,
          },
        },
        <String, Object?>{
          'code': 200,
          'data': <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'name': '示例.mp4',
                'size': 1234,
                'modified': '2026-07-15T11:00:00Z',
                'is_dir': false,
              },
            ],
            'total': 2,
          },
        },
      ];

      final entries = await client.listDirectory('/媒体', password: 'folder');

      expect(entries, hasLength(2));
      expect(entries.first.name, '电影');
      expect(entries.first.remotePath, '/媒体/电影');
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.size, 1234);
      final listRequests = api.requests
          .where((request) => request.path == '/api/fs/list')
          .toList();
      expect(listRequests, hasLength(2));
      expect(listRequests.first.headers['Authorization'], 'secret-token');
      expect(listRequests.first.data, containsPair('path', '/媒体'));
      expect(listRequests.first.data, containsPair('password', 'folder'));
      expect(listRequests.first.data, containsPair('page', 1));
      expect(listRequests.first.data, containsPair('per_page', 100));
      expect(listRequests.first.data, containsPair('refresh', false));
      expect(listRequests.last.data, containsPair('page', 2));
    });

    test('根目录列表使用名称生成规范路径和稳定标识', () async {
      await credentials.write(
        source.id,
        const CloudCredential(token: 'secret-token'),
      );
      api.pagedListResponses = <Map<String, Object?>>[
        <String, Object?>{
          'code': 200,
          'data': <String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'name': '示例.mp4',
                'size': 10,
                'modified': '2026-07-15T11:00:00Z',
                'is_dir': false,
              },
            ],
            'total': 1,
          },
        },
      ];

      final entries = await client.listDirectory('/');

      expect(entries.single.remotePath, '/示例.mp4');
      expect(entries.single.id, '/示例.mp4');
    });

    test('播放解析按需获取临时地址和请求头且不会写入凭据', () async {
      await credentials.write(
        source.id,
        const CloudCredential(token: 'secret-token'),
      );
      api.responses['/api/fs/get'] = <String, Object?>{
        'code': 200,
        'data': <String, Object?>{
          'name': '示例.mp4',
          'size': 1234,
          'modified': '2026-07-15T11:00:00Z',
          'is_dir': false,
          'raw_url': 'https://cdn.example.com/secret-link',
          'header': <String, Object?>{'Referer': 'https://drive.example.com/'},
        },
      };

      final file = await client.getFile('/示例.mp4');
      final playback = await client.resolvePlayback('/示例.mp4');

      expect(file.name, '示例.mp4');
      expect(playback.uri.toString(), 'https://cdn.example.com/secret-link');
      expect(playback.headers['Referer'], 'https://drive.example.com/');
      expect(
        playback.networkRoute,
        PlaybackNetworkRoute.inheritProxy,
      );
      expect(api.requests.where((r) => r.path == '/api/fs/get'), hasLength(2));
      expect((await credentials.read(source.id))?.toJson().toString(),
          isNot(contains('secret-link')));
      expect(playback.toString(), isNot(contains('secret-link')));
    });

    test('服务错误映射为不泄露敏感内容的领域异常', () async {
      api.responses['/api/auth/login'] = <String, Object?>{
        'code': 401,
        'message': 'password=secret-password token=secret-token',
      };

      await expectLater(
        client.authenticate(
          source,
          const CloudCredential(username: 'alice', password: 'secret-password'),
        ),
        throwsA(
          isA<CloudDriveException>()
              .having((e) => e.type, '类型', CloudDriveErrorType.authentication)
              .having((e) => e.toString(), '文本', isNot(contains('secret'))),
        ),
      );
    });

    test('请求 401 时使用保存的账号重新登录且仅重试一次', () async {
      await credentials.write(
        source.id,
        const CloudCredential(
          username: 'alice',
          password: 'secret-password',
          token: 'expired-token',
        ),
      );
      api.responseQueues['/api/fs/list'] = <Map<String, Object?>>[
        <String, Object?>{'code': 401, 'message': 'expired'},
        <String, Object?>{
          'code': 200,
          'data': <String, Object?>{'content': <Object?>[], 'total': 0},
        },
      ];
      api.responses['/api/auth/login'] = <String, Object?>{
        'code': 200,
        'data': <String, Object?>{'token': 'renewed-token'},
      };

      await client.listDirectory('/');

      expect(api.requests.where((r) => r.path == '/api/fs/list'), hasLength(2));
      expect(
          api.requests.where((r) => r.path == '/api/auth/login'), hasLength(1));
      expect((await credentials.read(source.id))?.token, 'renewed-token');
    });

    test('重认证后的第二次 401 直接抛认证错误且不循环', () async {
      await credentials.write(
        source.id,
        const CloudCredential(
          username: 'alice',
          password: 'secret-password',
          token: 'expired-token',
        ),
      );
      api.responseQueues['/api/fs/get'] = <Map<String, Object?>>[
        <String, Object?>{'code': 401},
        <String, Object?>{'code': 401},
      ];
      api.responses['/api/auth/login'] = <String, Object?>{
        'code': 200,
        'data': <String, Object?>{'token': 'renewed-token'},
      };

      await expectLater(
        client.getFile('/示例.mp4'),
        throwsA(isA<CloudDriveException>().having(
          (e) => e.type,
          '类型',
          CloudDriveErrorType.authentication,
        )),
      );

      expect(api.requests.where((r) => r.path == '/api/fs/get'), hasLength(2));
      expect(
          api.requests.where((r) => r.path == '/api/auth/login'), hasLength(1));
    });

    test('登录业务错误按认证权限和不存在分类', () async {
      for (final entry in <int, CloudDriveErrorType>{
        400: CloudDriveErrorType.authentication,
        401: CloudDriveErrorType.authentication,
        403: CloudDriveErrorType.permission,
        404: CloudDriveErrorType.notFound,
      }.entries) {
        api.responses['/api/auth/login'] = <String, Object?>{'code': entry.key};
        await expectLater(
          client.authenticate(
            source,
            const CloudCredential(username: 'alice', password: 'password'),
          ),
          throwsA(isA<CloudDriveException>().having(
            (e) => e.type,
            '类型',
            entry.value,
          )),
        );
      }
    });

    test('证书握手失败映射为证书错误', () async {
      api.errors['/api/auth/login'] = DioException(
        requestOptions: RequestOptions(path: '/api/auth/login'),
        type: DioExceptionType.connectionError,
        error: const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
      );

      await expectLater(
        client.authenticate(
          source,
          const CloudCredential(username: 'alice', password: 'password'),
        ),
        throwsA(isA<CloudDriveException>().having(
          (e) => e.type,
          '类型',
          CloudDriveErrorType.certificate,
        )),
      );
    });

    test('拒绝非 HTTP 地址和包含内嵌凭据的地址', () {
      for (final url in <String>[
        'ftp://drive.example.com',
        'https://user:password@drive.example.com',
        'not-a-url',
      ]) {
        expect(
          () => OpenListClient(
            source: CloudSource(
              id: 'invalid',
              type: CloudSourceType.openList,
              name: '无效',
              baseUrl: url,
              rootPaths: const ['/'],
            ),
            credentialStore: credentials,
            dio: Dio(),
          ),
          throwsA(isA<CloudDriveException>().having(
            (e) => e.type,
            '类型',
            CloudDriveErrorType.invalidAddress,
          )),
        );
      }
    });
  });
}

class _RecordingInterceptor extends Interceptor {
  final Map<String, Map<String, Object?>> responses =
      <String, Map<String, Object?>>{};
  List<Map<String, Object?>> pagedListResponses = <Map<String, Object?>>[];
  final Map<String, List<Map<String, Object?>>> responseQueues =
      <String, List<Map<String, Object?>>>{};
  final Map<String, DioException> errors = <String, DioException>{};
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);
    final error = errors[options.path];
    if (error != null) {
      handler.reject(error);
      return;
    }
    final queue = responseQueues[options.path];
    if (queue != null && queue.isNotEmpty) {
      handler.resolve(Response<Object?>(
        requestOptions: options,
        statusCode: 200,
        data: queue.removeAt(0),
      ));
      return;
    }
    if (options.path == '/api/fs/list' && pagedListResponses.isNotEmpty) {
      final page = (options.data as Map<String, Object?>)['page']! as int;
      handler.resolve(Response<Object?>(
        requestOptions: options,
        statusCode: 200,
        data: pagedListResponses[page - 1],
      ));
      return;
    }
    handler.resolve(Response<Object?>(
      requestOptions: options,
      statusCode: 200,
      data: responses[options.path],
    ));
  }
}
