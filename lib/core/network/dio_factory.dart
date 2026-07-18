import 'package:dio/dio.dart';
import 'package:kanyingyin/core/network/network_config.dart';

class DioFactory {
  DioFactory._();

  static Dio createForConfig(
    NetworkConfig config, {
    Map<String, Object?> defaultHeaders = const {},
    List<Interceptor> interceptors = const [],
  }) {
    // ignore: unnecessary_constructor_name
    final dio = Dio.new(
      BaseOptions(
        connectTimeout: config.connectTimeout,
        receiveTimeout: config.receiveTimeout,
        sendTimeout: config.sendTimeout,
        headers: defaultHeaders,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    dio.httpClientAdapter = config.createAdapter();
    dio.transformer = BackgroundTransformer();
    dio.interceptors.addAll(interceptors);
    return dio;
  }
}
