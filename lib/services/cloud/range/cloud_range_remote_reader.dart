import 'dart:io';

import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';

enum CloudRangeReaderEvent { reconnecting, refreshing }

abstract interface class CloudRangeRemoteReader {
  int? get totalLength;
  String get contentType;
  Stream<CloudRangeReaderEvent> get events;

  Future<CloudRangeRemoteMetadata> probe();

  Future<void> readTo(ByteRange range, File destination);

  Future<void> streamAll(IOSink destination);

  Future<void> close();
}

class CloudRangeRemoteResource {
  CloudRangeRemoteResource({
    required this.uri,
    Map<String, String> headers = const <String, String>{},
    this.totalLength,
    this.contentType,
  }) : headers = Map<String, String>.unmodifiable(headers);

  final Uri uri;
  final Map<String, String> headers;
  final int? totalLength;
  final String? contentType;

  CloudRangeRemoteResource copyWith({
    Uri? uri,
    Map<String, String>? headers,
    int? totalLength,
    String? contentType,
  }) =>
      CloudRangeRemoteResource(
        uri: uri ?? this.uri,
        headers: headers ?? this.headers,
        totalLength: totalLength ?? this.totalLength,
        contentType: contentType ?? this.contentType,
      );
}

class CloudRangeRemoteMetadata {
  const CloudRangeRemoteMetadata({
    required this.totalLength,
    required this.contentType,
    required this.supportsRanges,
  });

  final int totalLength;
  final String contentType;
  final bool supportsRanges;
}

class CloudRangeRemoteProtocolException implements Exception {
  const CloudRangeRemoteProtocolException(this.message);

  final String message;

  @override
  String toString() => 'CloudRangeRemoteProtocolException($message)';
}

class CloudRangeRemoteAuthenticationException implements Exception {
  const CloudRangeRemoteAuthenticationException(this.message);

  final String message;

  @override
  String toString() => 'CloudRangeRemoteAuthenticationException($message)';
}

class CloudRangeRemoteTransportException implements Exception {
  const CloudRangeRemoteTransportException(this.message);

  final String message;

  @override
  String toString() => 'CloudRangeRemoteTransportException($message)';
}
