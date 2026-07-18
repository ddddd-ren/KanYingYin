import 'dart:io';

import 'package:dio/io.dart';

class NetworkConfig {
  const NetworkConfig({
    this.connectTimeout = const Duration(seconds: 12),
    this.receiveTimeout = const Duration(seconds: 12),
    this.sendTimeout,
    this.proxyHost,
    this.proxyPort,
    this.allowBadCertificates = false,
  });

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration? sendTimeout;
  final String? proxyHost;
  final int? proxyPort;
  final bool allowBadCertificates;

  bool get hasProxy => proxyHost != null && proxyPort != null;

  IOHttpClientAdapter createAdapter() {
    return IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        if (hasProxy) {
          client.findProxy = (_) => 'PROXY $proxyHost:$proxyPort';
        }
        if (allowBadCertificates) {
          client.badCertificateCallback = (cert, host, port) => true;
        }
        return client;
      },
    );
  }

  NetworkConfig copyWith({
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    String? proxyHost,
    int? proxyPort,
    bool? clearProxy,
    bool? allowBadCertificates,
  }) {
    final shouldClearProxy = clearProxy ?? false;
    return NetworkConfig(
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      proxyHost: shouldClearProxy ? null : proxyHost ?? this.proxyHost,
      proxyPort: shouldClearProxy ? null : proxyPort ?? this.proxyPort,
      allowBadCertificates: allowBadCertificates ?? this.allowBadCertificates,
    );
  }
}
