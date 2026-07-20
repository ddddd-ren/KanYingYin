import 'dart:async';

import 'package:dio/dio.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_models.dart';
import 'package:kanyingyin/services/cloud/quark/quark_request_policy.dart';
import 'package:kanyingyin/services/cloud/quark/quark_response_parser.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_transfer_task.dart';

typedef QuarkRequestDelay = Future<void> Function(Duration duration);

abstract interface class QuarkApi {
  String get sessionCookie;

  Future<QuarkAccount> getAccount();

  Future<QuarkDirectoryPage> listDirectoryPage({
    required String directoryId,
    required int page,
    int size = 50,
  });

  Future<QuarkPlaybackLink> resolvePlayback(String fileId);

  Future<void> close();
}

abstract interface class QuarkShareApi {
  Future<String> getShareToken({
    required String shareId,
    required String passcode,
  });

  Future<QuarkDirectoryPage> listSharePage({
    required String shareId,
    required String shareToken,
    required String directoryId,
    required int page,
    int size = 50,
  });

  Future<String> saveShare({
    required String shareId,
    required String shareToken,
    required List<String> fileIds,
    required List<String> fileTokens,
    required String targetDirectoryId,
  });

  Future<QuarkTransferTask> queryTask({
    required String taskId,
    required int retryIndex,
  });

  Future<void> close();
}

class QuarkApiClient implements QuarkApi, QuarkShareApi {
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
  static final Uri _shareTokenUri =
      Uri.https('drive-pc.quark.cn', '/1/clouddrive/share/sharepage/token');
  static final Uri _shareDetailUri =
      Uri.https('drive-pc.quark.cn', '/1/clouddrive/share/sharepage/detail');
  static final Uri _shareSaveUri =
      Uri.https('drive-pc.quark.cn', '/1/clouddrive/share/sharepage/save');
  static final Uri _taskUri =
      Uri.https('drive-pc.quark.cn', '/1/clouddrive/task');

  String _cookie;
  final Dio _dio;
  final bool _ownsDio;
  final QuarkRequestPolicy _policy;
  final QuarkResponseParser _parser;
  final QuarkRequestDelay _delay;

  @override
  String get sessionCookie => _cookie;

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
  Future<QuarkPlaybackLink> resolvePlayback(String fileId) async {
    final json = await _request(
      'POST',
      _downloadUri,
      queryParameters: const <String, Object?>{'pr': 'ucpro', 'fr': 'pc'},
      data: <String, Object?>{
        'fids': <String>[fileId],
      },
    );
    return _parser.parseDownload(json, fileId: fileId);
  }

  @override
  Future<String> getShareToken({
    required String shareId,
    required String passcode,
  }) async {
    final json = await _request(
      'POST',
      _shareTokenUri,
      queryParameters: const <String, Object?>{'pr': 'ucpro', 'fr': 'pc'},
      data: <String, Object?>{'pwd_id': shareId, 'passcode': passcode},
    );
    return _parser.parseShareToken(json);
  }

  @override
  Future<QuarkDirectoryPage> listSharePage({
    required String shareId,
    required String shareToken,
    required String directoryId,
    required int page,
    int size = 50,
  }) async {
    final json = await _request(
      'GET',
      _shareDetailUri,
      queryParameters: <String, Object?>{
        'pr': 'ucpro',
        'fr': 'pc',
        'pwd_id': shareId,
        'stoken': shareToken,
        'pdir_fid': directoryId,
        'force': 0,
        '_page': page,
        '_size': size,
        '_fetch_banner': 0,
        '_fetch_share': 0,
        '_fetch_total': 1,
        '_sort': 'file_type:asc,updated_at:desc',
        'ver': 2,
      },
    );
    return _parser.parseDirectoryPage(json);
  }

  @override
  Future<String> saveShare({
    required String shareId,
    required String shareToken,
    required List<String> fileIds,
    required List<String> fileTokens,
    required String targetDirectoryId,
  }) async {
    final json = await _request(
      'POST',
      _shareSaveUri,
      queryParameters: const <String, Object?>{
        'pr': 'ucpro',
        'fr': 'pc',
        'app': 'clouddrive',
      },
      data: <String, Object?>{
        'fid_list': fileIds,
        'fid_token_list': fileTokens,
        'to_pdir_fid': targetDirectoryId,
        'pwd_id': shareId,
        'stoken': shareToken,
        'pdir_fid': '0',
        'scene': 'link',
      },
    );
    return _parser.parseSaveTaskId(json);
  }

  @override
  Future<QuarkTransferTask> queryTask({
    required String taskId,
    required int retryIndex,
  }) async {
    final json = await _request(
      'GET',
      _taskUri,
      queryParameters: <String, Object?>{
        'pr': 'ucpro',
        'fr': 'pc',
        'task_id': taskId,
        'retry_index': retryIndex,
      },
    );
    return _parser.parseTask(json);
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
        _mergeResponseCookies(response.headers.map['set-cookie']);
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

  void _mergeResponseCookies(List<String>? setCookies) {
    if (setCookies == null || setCookies.isEmpty) return;
    final values = <String, String>{};
    for (final part in _cookie.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      values[part.substring(0, separator).trim()] =
          part.substring(separator + 1).trim();
    }
    for (final setCookie in setCookies) {
      final pair = setCookie.split(';').first;
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      values[name] = value;
    }
    _cookie =
        values.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  @override
  Future<void> close() async {
    if (_ownsDio) _dio.close(force: true);
  }
}
