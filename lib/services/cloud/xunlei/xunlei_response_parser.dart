import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';

class XunleiResponseParser {
  const XunleiResponseParser({this.now = _systemNow});

  final DateTime Function() now;

  XunleiSession parseSession(Map<String, Object?> json) {
    final tokenType = _requiredString(json, 'token_type');
    final accessToken = _requiredString(json, 'access_token');
    final refreshToken = _requiredString(json, 'refresh_token');
    final userId = _requiredString(json, 'user_id');
    final expiresIn = _positiveInt(json['expires_in']);
    if (expiresIn == null) _incompatible();
    return XunleiSession(
      tokenType: tokenType,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: now().toUtc().add(Duration(seconds: expiresIn)),
      userId: userId,
    );
  }

  XunleiAccount parseAccount(
    Map<String, Object?> json, {
    String? fallbackUserId,
  }) {
    final userId =
        _optionalString(json['user_id']) ?? _optionalString(fallbackUserId);
    if (userId == null) _incompatible();
    final phone = _optionalString(json['phone']);
    final name = _optionalString(json['name']);
    final label = phone == null ? name ?? '迅雷账号' : _maskAccount(phone);
    return XunleiAccount(userId: userId, accountLabel: label);
  }

  XunleiDirectoryPage parseDirectoryPage(Map<String, Object?> json) {
    final values = json['files'];
    if (values is! List) _incompatible();
    final files = <XunleiFile>[];
    for (final value in values) {
      if (value is! Map) _incompatible();
      files.add(_parseFile(Map<String, Object?>.from(value)));
    }
    final pageToken = _optionalString(json['next_page_token']);
    return XunleiDirectoryPage(
      files: List<XunleiFile>.unmodifiable(files),
      nextPageToken: pageToken,
    );
  }

  XunleiFileDetail parseFileDetail(Map<String, Object?> json) {
    final file = _parseFile(json);
    if (file.isDirectory) _incompatible();
    final originalUri = _httpsUri(json['web_content_link']);
    final transcodeUris = <Uri>[];
    final medias = json['medias'];
    if (medias is List) {
      for (final value in medias) {
        if (value is! Map) continue;
        final link = value['link'];
        if (link is! Map) continue;
        final uri = _optionalHttpsUri(link['url']);
        if (uri != null) transcodeUris.add(uri);
      }
    }
    return XunleiFileDetail(
      file: file,
      originalUri: originalUri,
      transcodeUris: List<Uri>.unmodifiable(transcodeUris),
    );
  }

  XunleiVerificationRequired parseVerificationRequired(
    Map<String, Object?> json,
  ) {
    if (_optionalString(json['error']) != 'review_panel') _incompatible();
    final uri = _httpsUri(json['reviewurl']);
    final creditKey = _requiredString(json, 'creditkey');
    return XunleiVerificationRequired(uri: uri, creditKey: creditKey);
  }

  XunleiFile _parseFile(Map<String, Object?> json) {
    final kind = _requiredString(json, 'kind');
    final isDirectory = switch (kind) {
      'drive#folder' => true,
      'drive#file' => false,
      _ => _incompatible(),
    };
    final size = _nonNegativeInt(json['size']);
    if (size == null) _incompatible();
    final modifiedValue = _optionalString(json['modified_time']);
    final modifiedAt = modifiedValue == null
        ? null
        : DateTime.tryParse(modifiedValue)?.toUtc();
    if (modifiedValue != null && modifiedAt == null) _incompatible();
    return XunleiFile(
      id: _requiredString(json, 'id'),
      parentId: _optionalString(json['parent_id']) ?? '',
      name: _requiredString(json, 'name'),
      size: size,
      modifiedAt: modifiedAt,
      isDirectory: isDirectory,
    );
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final value = _optionalString(json[key]);
    if (value == null) _incompatible();
    return value;
  }

  String? _optionalString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  int? _positiveInt(Object? value) {
    final number = value is num ? value.toInt() : int.tryParse('$value');
    return number != null && number > 0 ? number : null;
  }

  int? _nonNegativeInt(Object? value) {
    final number = value is num ? value.toInt() : int.tryParse('$value');
    return number != null && number >= 0 ? number : null;
  }

  Uri _httpsUri(Object? value) {
    final uri = _optionalHttpsUri(value);
    if (uri == null) _incompatible();
    return uri;
  }

  Uri? _optionalHttpsUri(Object? value) {
    final text = _optionalString(value);
    final uri = text == null ? null : Uri.tryParse(text);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri
        : null;
  }

  String _maskAccount(String value) {
    if (value.length < 7) return '***';
    return '${value.substring(0, 3)}****${value.substring(value.length - 4)}';
  }

  Never _incompatible() => throw const CloudDriveException(
        CloudDriveErrorType.incompatible,
      );

  static DateTime _systemNow() => DateTime.now();
}
