import 'package:kanyingyin/services/cloud/baidu/baidu_models.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';

class BaiduResponseParser {
  const BaiduResponseParser();

  BaiduAccount parseAccount(Map<String, Object?> json) {
    _ensureSuccess(json);
    final displayName = _nonEmptyString(json['netdisk_name']) ??
        _nonEmptyString(json['baidu_name']);
    final userId = _integer(json['uk']);
    final vipType = _integer(json['vip_type']);
    if (displayName == null || userId == null || vipType == null) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return BaiduAccount(
      displayName: displayName,
      userId: userId.toString(),
      vipType: vipType,
    );
  }

  BaiduDirectoryPage parseDirectoryPage(Map<String, Object?> json) {
    _ensureSuccess(json);
    final list = json['list'];
    if (list is! List<Object?>) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return BaiduDirectoryPage(<BaiduFileEntry>[
      for (final value in list) _parseEntry(value),
    ]);
  }

  BaiduFileDetails parseFileDetails(
    Map<String, Object?> json, {
    required String expectedFsId,
  }) {
    _ensureSuccess(json);
    final list = json['list'];
    if (list is! List<Object?> || list.length != 1) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    final value = list.single;
    final entry = _parseEntry(
      value,
      nameKey: 'filename',
      fallbackNameKey: 'server_filename',
    );
    if (entry.fsId != expectedFsId || value is! Map<Object?, Object?>) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    final map = Map<String, Object?>.from(value);
    final dlink = _nonEmptyString(map['dlink']);
    final uri = dlink == null ? null : Uri.tryParse(dlink);
    if (dlink != null &&
        (uri == null || uri.scheme != 'https' || !uri.hasAuthority)) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return BaiduFileDetails(
      fsId: entry.fsId,
      path: entry.path,
      name: entry.name,
      size: entry.size,
      modifiedAt: entry.modifiedAt,
      isDirectory: entry.isDirectory,
      downloadUri: uri,
    );
  }

  BaiduFileEntry _parseEntry(
    Object? value, {
    String nameKey = 'server_filename',
    String? fallbackNameKey,
  }) {
    if (value is! Map<Object?, Object?>) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    final json = Map<String, Object?>.from(value);
    final fsId = _integer(json['fs_id']);
    final path = _nonEmptyString(json['path']);
    final name = _nonEmptyString(json[nameKey]) ??
        (fallbackNameKey == null
            ? null
            : _nonEmptyString(json[fallbackNameKey]));
    final size = _integer(json['size']);
    final isDirectory = _integer(json['isdir']);
    final modifiedAt = _integer(json['server_mtime']);
    if (fsId == null ||
        fsId < 0 ||
        path == null ||
        name == null ||
        size == null ||
        size < 0 ||
        (isDirectory != 0 && isDirectory != 1) ||
        modifiedAt == null ||
        modifiedAt < 0) {
      throw const CloudDriveException(CloudDriveErrorType.incompatible);
    }
    return BaiduFileEntry(
      fsId: fsId.toString(),
      path: path,
      name: name,
      size: size,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        modifiedAt * Duration.millisecondsPerSecond,
        isUtc: true,
      ),
      isDirectory: isDirectory == 1,
    );
  }

  void _ensureSuccess(Map<String, Object?> json) {
    final errno = _integer(json['errno']);
    if (errno == 0) return;
    final type = switch (errno) {
      -6 || 111 => CloudDriveErrorType.authentication,
      -7 => CloudDriveErrorType.permission,
      -9 => CloudDriveErrorType.notFound,
      31034 => CloudDriveErrorType.rateLimited,
      _ => CloudDriveErrorType.incompatible,
    };
    throw CloudDriveException(type);
  }

  int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }

  String? _nonEmptyString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
