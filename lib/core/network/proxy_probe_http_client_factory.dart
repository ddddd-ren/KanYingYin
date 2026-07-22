import 'dart:io';

/// 创建代理连通性探测使用的 HTTP 客户端。
///
/// 探测客户端始终沿用系统 TLS 证书校验，只负责配置超时和路由方式。
class ProxyProbeHttpClientFactory {
  const ProxyProbeHttpClientFactory({required this.connectionTimeout});

  final Duration connectionTimeout;

  HttpClient createDirect({HttpClient Function()? createClient}) =>
      _create(proxy: 'DIRECT', createClient: createClient);

  HttpClient createProxied({
    required String host,
    required int port,
    HttpClient Function()? createClient,
  }) =>
      _create(
        proxy: 'PROXY $host:$port',
        createClient: createClient,
      );

  HttpClient _create({
    required String proxy,
    HttpClient Function()? createClient,
  }) {
    final client = (createClient ?? HttpClient.new)();
    client.connectionTimeout = connectionTimeout;
    client.findProxy = (_) => proxy;
    return client;
  }
}
