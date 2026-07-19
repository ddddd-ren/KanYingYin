import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_models.dart';

class QuarkResponseParser {
  const QuarkResponseParser();

  static const String incompatibleMessage = '当前版本暂不兼容夸克接口';

  void ensureSuccess(Object? value) {
    final json = _map(value);
    final code = _int(json['code']);
    final status = _int(json['status']);
    if ((code == null || code == 0) &&
        (status == null || (status >= 200 && status < 300))) {
      return;
    }
    final message = json['message'] is String ? json['message'] as String : '';
    throw CloudDriveException(
      _errorType(status: status, code: code, message: message),
    );
  }

  QuarkAccount parseAccount(Object? value) {
    ensureSuccess(value);
    final data = _requiredMap(_map(value)['data']);
    final nickname = data['nickname'];
    if (nickname is! String || nickname.trim().isEmpty) {
      throw _incompatible();
    }
    return QuarkAccount(nickname: nickname.trim());
  }

  QuarkDirectoryPage parseDirectoryPage(Object? value) {
    ensureSuccess(value);
    final json = _map(value);
    final data = _requiredMap(json['data']);
    final metadata = _requiredMap(json['metadata']);
    final rawItems = data['list'];
    final page = _int(metadata['_page']);
    final size = _int(metadata['_size']);
    final total = _int(metadata['_total']);
    if (rawItems is! List || page == null || size == null || total == null) {
      throw _incompatible();
    }
    final items = <QuarkFile>[];
    for (final raw in rawItems) {
      final item = _requiredMap(raw);
      final id = item['fid'];
      final name = item['file_name'];
      final fileFlag = item['file'];
      final directoryFlag = item['dir'];
      final itemSize = _int(item['size']);
      if (id is! String ||
          id.isEmpty ||
          name is! String ||
          itemSize == null ||
          (fileFlag is! bool && directoryFlag is! bool)) {
        throw _incompatible();
      }
      final timestamp = _int(item['updated_at']) ?? _int(item['l_updated_at']);
      items.add(QuarkFile(
        id: id,
        name: name,
        isDirectory:
            directoryFlag is bool ? directoryFlag : !(fileFlag as bool),
        size: itemSize,
        modifiedAt: timestamp == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(timestamp),
        category: _int(item['category']) ?? 0,
        shareFileToken: item['share_fid_token'] is String
            ? item['share_fid_token'] as String
            : null,
      ));
    }
    return QuarkDirectoryPage(
      items: List<QuarkFile>.unmodifiable(items),
      page: page,
      size: size,
      total: total,
    );
  }

  QuarkPlaybackLink parsePlayback(Object? value) {
    ensureSuccess(value);
    final data = _map(value)['data'];
    if (data is! List || data.isEmpty) throw _incompatible();
    final item = _requiredMap(data.first);
    final fileId = item['fid'];
    final url = item['download_url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (fileId is! String ||
        fileId.isEmpty ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      throw _incompatible();
    }
    return QuarkPlaybackLink(fileId: fileId, uri: uri);
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw _incompatible();
    return Map<String, Object?>.from(value);
  }

  static Map<String, Object?> _requiredMap(Object? value) {
    if (value is! Map) throw _incompatible();
    return Map<String, Object?>.from(value);
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static CloudDriveErrorType _errorType({
    required int? status,
    required int? code,
    required String message,
  }) {
    final normalized = message.toLowerCase();
    if (status == 401 ||
        code == 401 ||
        normalized.contains('登录失效') ||
        normalized.contains('cookie')) {
      return CloudDriveErrorType.authentication;
    }
    if (status == 403 || code == 403) return CloudDriveErrorType.permission;
    if (status == 404 || code == 404 || normalized.contains('不存在')) {
      return CloudDriveErrorType.notFound;
    }
    if (status == 429 || code == 429 || normalized.contains('频繁')) {
      return CloudDriveErrorType.rateLimited;
    }
    return CloudDriveErrorType.incompatible;
  }

  static CloudDriveException _incompatible() => const CloudDriveException(
        CloudDriveErrorType.incompatible,
        message: incompatibleMessage,
      );
}
