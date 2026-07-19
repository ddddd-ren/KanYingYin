import 'dart:async';

import 'package:dio/dio.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_models.dart';
import 'package:kanyingyin/services/cloud/quark/quark_request_policy.dart';
import 'package:kanyingyin/services/cloud/quark/quark_response_parser.dart';

typedef QuarkRequestDelay = Future<void> Function(Duration duration);

abstract interface class QuarkApi {
  Future<QuarkAccount> getAccount();

  Future<QuarkDirectoryPage> listDirectoryPage({
    required String directoryId,
    required int page,
    int size = 50,
  });

  Future<QuarkPlaybackLink> resolveDownload(String fileId);

  Future<void> close();
}

class QuarkApiClient implements QuarkApi {
  QuarkApiClient({
    required String cookie,
    Dio? dio,
    QuarkRequestPolicy policy = const QuarkRequestPolicy(),
    QuarkResponseParser parser = const QuarkResponseParser(),
    QuarkRequestDelay? delay,
  })  : _cookie = cookie.trim(),
        _dio = dio ?? Dio(),
        _ownsDio = dio == null,
        _policy = policy,
        _parser = parser,
        _delay = delay ?? Future<void>.delayed {
    _dio.options
      ..connectTimeout = const Duration(seconds: 10)
      ..sendTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30);
  }

  static final Uri _accountUri = Uri.https(
    'pan.quark.cn',
    '/account/info',
    <String, String>{'fr': 'pc', 'platform': 'pc'},
  );
  static final Uri _directoryUri =
      Uri.https('drive.quark.cn', '/1/clouddrive/file/sort');
  static final Uri _downloadUri =
      Uri.https('drive.quark.cn', '/1/clouddrive/file/download');

  final String _cookie;
  final Dio _dio;
  final bool _ownsDio;
  final QuarkRequestPolicy _policy;
  final QuarkResponseParser _parser;
  final QuarkRequestDelay _delay;

  @override
  Future<QuarkAccount> getAccount() async =>
      _parser.parseAccount(await _request('GET', _accountUri));

  @override
  Future<QuarkDirectoryPage> listDirectoryPage({
    required String directoryId,
    required int page,
    int size = 50,
  }) async {
    final json = await _request(
      'GET',
      _directoryUri,
      queryParameters: <String, Object?>{
        'pr': 'ucpro',
        'fr': 'pc',
        'pdir_fid': directoryId,
        '_page': page,
        '_size': size,
        '_fetch_total': 1,
        '_fetch_sub_dirs': 0,
        '_sort': 'file_type:asc,updated_at:desc',
        'fetch_all_file': 1,
        'fetch_risk_file_name': 1,
      },
    );
    return _parser.parseDirectoryPage(json);
  }

  @override
  Future<QuarkPlaybackLink> resolveDownload(String fileId) async {
    final json = await _request(
      'POST',
      _downloadUri,
      queryParameters: const <String, Object?>{'pr': 'ucpro', 'fr': 'pc'},
      data: <String, Object?>{
        'fids': <String>[fileId],
      },
    );
    return _parser.parsePlayback(json);
  }

  Future<Object?> _request(
    String method,
    Uri uri, {
    Map<String, Object?>? queryParameters,
    Object? data,
  }) async {
    final requestUri = queryParameters == null
        ? uri
        : uri.replace(queryParameters: <String, String>{
            ...uri.queryParameters,
            for (final entry in queryParameters.entries)
              entry.key: entry.value.toString(),
          });
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _dio.requestUri<Object?>(
          requestUri,
          data: data,
          options: Options(
            method: method,
            headers: _policy.headersFor(requestUri, cookie: _cookie),
            validateStatus: (_) => true,
          ),
        );
        final status = response.statusCode ?? 0;
        if (_policy.shouldRetry(statusCode: status, attempt: attempt)) {
          await _delay(_policy.retryDelay(attempt));
          continue;
        }
        if (status == 401) {
          throw const CloudDriveException(CloudDriveErrorType.authentication);
        }
        if (status == 403) {
          throw const CloudDriveException(CloudDriveErrorType.permission);
        }
        if (status == 404) {
          throw const CloudDriveException(CloudDriveErrorType.notFound);
        }
        if (status == 408) {
          throw const CloudDriveException(CloudDriveErrorType.timeout);
        }
        if (status == 429) {
          throw const CloudDriveException(CloudDriveErrorType.rateLimited);
        }
        if (status < 200 || status >= 300) {
          throw const CloudDriveException(CloudDriveErrorType.network);
        }
        _parser.ensureSuccess(response.data);
        return response.data;
      } on DioException catch (error) {
        if (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.receiveTimeout) {
          throw const CloudDriveException(CloudDriveErrorType.timeout);
        }
        if (attempt < 2) {
          await _delay(_policy.retryDelay(attempt));
          continue;
        }
        throw const CloudDriveException(CloudDriveErrorType.network);
      }
    }
    throw const CloudDriveException(CloudDriveErrorType.network);
  }

  @override
  Future<void> close() async {
    if (_ownsDio) _dio.close(force: true);
  }
}
