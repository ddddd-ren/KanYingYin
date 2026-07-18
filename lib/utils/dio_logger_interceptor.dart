import 'package:dio/dio.dart';
import 'package:kanyingyin/utils/logger.dart';

class DioLoggerInterceptor extends Interceptor {
  static const _startedAtExtraKey = '_kanyingyinStartedAt';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtExtraKey] = DateTime.now();
    AppLogger().d('HTTP: --> ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    final elapsed = _elapsed(response.requestOptions);
    AppLogger().d(
      'HTTP: <-- ${response.statusCode} '
      '${response.requestOptions.method} ${response.requestOptions.uri}'
      '${elapsed == null ? '' : ' ${elapsed}ms'}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final elapsed = _elapsed(err.requestOptions);
    final statusCode = err.response?.statusCode;
    final status = statusCode == null ? err.type.name : statusCode.toString();
    AppLogger().w(
      'HTTP: <-- $status ${err.requestOptions.method} ${err.requestOptions.uri}'
      '${elapsed == null ? '' : ' ${elapsed}ms'}',
      error: err.message,
    );
    handler.next(err);
  }

  int? _elapsed(RequestOptions options) {
    final startedAt = options.extra[_startedAtExtraKey];
    if (startedAt is! DateTime) return null;
    return DateTime.now().difference(startedAt).inMilliseconds;
  }
}
