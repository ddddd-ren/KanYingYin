import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_models.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_transfer_task.dart';

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

  QuarkPlaybackLink parsePlayback(
    Object? value, {
    required String fileId,
  }) {
    ensureSuccess(value);
    final data = _requiredMap(_map(value)['data']);
    final rawVideos = data['video_list'];
    if (fileId.isEmpty) throw _incompatible();
    if (rawVideos is! List) {
      throw const QuarkNoTranscodingLinkException();
    }
    Uri? selectedUri;
    var selectedRank = -1;
    var selectedFormatRank = -1;
    for (final rawVideo in rawVideos) {
      final video = _requiredMap(rawVideo);
      final videoInfo = video['video_info'];
      if (videoInfo is! Map) continue;
      final info = Map<String, Object?>.from(videoInfo);
      final url = info['url'];
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      final resolution = video['resolution'];
      final rank = _resolutionRank(resolution is String ? resolution : '');
      final formatRank = _formatRank(video, info, uri);
      if (selectedUri == null ||
          rank > selectedRank ||
          (rank == selectedRank && formatRank > selectedFormatRank)) {
        selectedUri = uri;
        selectedRank = rank;
        selectedFormatRank = formatRank;
      }
    }
    if (selectedUri == null) {
      throw const QuarkNoTranscodingLinkException();
    }
    return QuarkPlaybackLink(fileId: fileId, uri: selectedUri);
  }

  QuarkPlaybackLink parseDownload(
    Object? value, {
    required String fileId,
  }) {
    ensureSuccess(value);
    final data = _map(value)['data'];
    if (fileId.isEmpty || data is! List) throw _incompatible();
    for (final rawDownload in data) {
      if (rawDownload is! Map) continue;
      final download = Map<String, Object?>.from(rawDownload);
      final url = download['download_url'];
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      return QuarkPlaybackLink(
        fileId: fileId,
        uri: uri,
        type: QuarkPlaybackLinkType.originalDownload,
      );
    }
    throw _incompatible();
  }

  String parseShareToken(Object? value) {
    ensureSuccess(value);
    final data = _requiredMap(_map(value)['data']);
    final token = data['stoken'];
    if (token is! String || token.isEmpty) throw _incompatible();
    return token;
  }

  String parseSaveTaskId(Object? value) {
    ensureSuccess(value);
    final data = _requiredMap(_map(value)['data']);
    final taskId = data['task_id'];
    if (taskId is! String || taskId.isEmpty) throw _incompatible();
    return taskId;
  }

  QuarkTransferTask parseTask(Object? value) {
    ensureSuccess(value);
    final data = _requiredMap(_map(value)['data']);
    final status = _int(data['status']);
    final taskId = data['task_id'];
    if (status == null || taskId is! String || taskId.isEmpty) {
      throw _incompatible();
    }
    final savedFileIds = <String>[];
    final saveAs = data['save_as'];
    if (saveAs is Map) {
      final rawIds = saveAs['save_as_top_fids'];
      if (rawIds is List) savedFileIds.addAll(rawIds.whereType<String>());
    }
    return QuarkTransferTask(
      id: taskId,
      status: status == 2
          ? QuarkTransferTaskStatus.succeeded
          : QuarkTransferTaskStatus.pending,
      title: data['task_title'] is String ? data['task_title'] as String : null,
      savedFileIds: List<String>.unmodifiable(savedFileIds),
    );
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

  static int _resolutionRank(String value) => switch (value.toLowerCase()) {
        '4k' => 6,
        '2k' => 5,
        'super' => 4,
        'high' => 3,
        'normal' => 2,
        'low' => 1,
        _ => 0,
      };

  static int _formatRank(
    Map<String, Object?> video,
    Map<String, Object?> info,
    Uri uri,
  ) {
    final format = <Object?>[
      video['format'],
      video['support'],
      info['format'],
      info['type'],
    ].whereType<String>().join(' ').toLowerCase();
    if (format.contains('fmp4')) return 2;
    if (format.contains('m3u8') || uri.path.toLowerCase().endsWith('.m3u8')) {
      return 1;
    }
    return 0;
  }

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
    if (code == 32003 || normalized.contains('capacity limit')) {
      return CloudDriveErrorType.insufficientSpace;
    }
    if (normalized.contains('提取码') || normalized.contains('passcode')) {
      return CloudDriveErrorType.invalidPasscode;
    }
    if (normalized.contains('分享失效') || normalized.contains('已失效')) {
      return CloudDriveErrorType.shareExpired;
    }
    return CloudDriveErrorType.incompatible;
  }

  static CloudDriveException _incompatible() => const CloudDriveException(
        CloudDriveErrorType.incompatible,
        message: incompatibleMessage,
      );
}
