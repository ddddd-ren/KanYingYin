import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_models.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_request_policy.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_response_parser.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

abstract interface class BaiduApi {
  Future<BaiduAccount> account();

  Future<List<BaiduFileEntry>> listDirectory(CloudRemoteRef directory);

  Future<BaiduFileDetails> fileDetails(
    CloudRemoteRef file, {
    required bool includeDownloadLink,
  });

  Future<void> close();
}

class BaiduApiClient implements BaiduApi {
  BaiduApiClient({
    required this.accessToken,
    Dio? dio,
    BaiduResponseParser parser = const BaiduResponseParser(),
    this.pageSize = 1000,
    Future<void> Function(Duration)? delay,
    this.maxRateLimitRetries = 3,
  })  : assert(pageSize > 0),
        assert(maxRateLimitRetries >= 0 && maxRateLimitRetries <= 3),
        _dio = dio ?? Dio(),
        _parser = parser,
        _delay = delay ?? Future<void>.delayed;

  static const List<Duration> _rateLimitDelays = <Duration>[
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  final String accessToken;
  final Dio _dio;
  final BaiduResponseParser _parser;
  final int pageSize;
  final Future<void> Function(Duration) _delay;
  final int maxRateLimitRetries;
  bool _closed = false;

  @override
  Future<BaiduAccount> account() async => _parser.parseAccount(
        await _get(BaiduEndpoints.account, <String, Object?>{
          'method': 'uinfo',
        }),
      );

  @override
  Future<List<BaiduFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async {
    final entries = <BaiduFileEntry>[];
    final seenIds = <String>{};
    final pageFingerprints = <String>{};
    var start = 0;
    for (var pageIndex = 0; pageIndex < 10000; pageIndex++) {
      final page = _parser.parseDirectoryPage(
        await _get(BaiduEndpoints.file, <String, Object?>{
          'method': 'list',
          'dir': directory.path,
          'start': start,
          'limit': pageSize,
          'order': 'name',
        }),
      );
      if (page.entries.isEmpty) break;
      final fingerprint = page.entries.map((entry) => entry.fsId).join(',');
      if (!pageFingerprints.add(fingerprint)) {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      var added = 0;
      for (final entry in page.entries) {
        if (seenIds.add(entry.fsId)) {
          entries.add(entry);
          added++;
        }
      }
      if (added == 0) {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      start += page.entries.length;
      if (page.entries.length < pageSize) break;
    }
    return List<BaiduFileEntry>.unmodifiable(entries);
  }

  @override
  Future<BaiduFileDetails> fileDetails(
    CloudRemoteRef file, {
    required bool includeDownloadLink,
  }) async {
    final fsId = int.tryParse(file.id);
    if (fsId == null || fsId < 0) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return _parser.parseFileDetails(
      await _get(BaiduEndpoints.multimedia, <String, Object?>{
        'method': 'filemetas',
        'fsids': jsonEncode(<int>[fsId]),
        'dlink': includeDownloadLink ? 1 : 0,
      }),
      expectedFsId: file.id,
    );
  }

  Future<Map<String, Object?>> _get(
    Uri endpoint,
    Map<String, Object?> queryParameters,
  ) async {
    if (_closed) throw StateError('百度 API 客户端已关闭');
    var rateLimitAttempt = 0;
    while (true) {
      try {
        final response = await _dio.get<Object?>(
          endpoint.toString(),
          queryParameters: <String, Object?>{
            ...queryParameters,
            'access_token': accessToken,
          },
          options: Options(
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        final decoded = response.data is String
            ? jsonDecode(response.data! as String)
            : response.data;
        if (decoded is! Map<Object?, Object?>) {
          throw const CloudDriveException(CloudDriveErrorType.incompatible);
        }
        return Map<String, Object?>.from(decoded);
      } on CloudDriveException {
        rethrow;
      } on DioException catch (error) {
        if (error.response?.statusCode == 429 &&
            rateLimitAttempt < maxRateLimitRetries) {
          await _delay(_rateLimitDelays[rateLimitAttempt]);
          rateLimitAttempt++;
          continue;
        }
        throw CloudDriveException(_mapDioError(error));
      } on Object {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
    }
  }

  CloudDriveErrorType _mapDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 429) return CloudDriveErrorType.rateLimited;
    if (statusCode == 401 || statusCode == 403) {
      return CloudDriveErrorType.authentication;
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return CloudDriveErrorType.timeout;
    }
    if (error.type == DioExceptionType.connectionError) {
      return CloudDriveErrorType.network;
    }
    return CloudDriveErrorType.incompatible;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _dio.close(force: true);
  }
}
