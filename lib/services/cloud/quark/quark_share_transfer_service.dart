import 'dart:async';

import 'package:kanyingyin/modules/cloud/quark/quark_share_entry.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_transfer_task.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_api_client.dart';

typedef QuarkTransferDelay = Future<void> Function(Duration duration);

abstract interface class QuarkShareTransfer {
  Future<QuarkShareInspection> inspectShare(
    String shareUrl, {
    String? passcode,
  });

  Future<String> saveShare({
    required String shareId,
    required List<QuarkShareEntry> entries,
    required String targetDirectoryId,
  });

  Future<QuarkTransferTask> queryTask(
    String taskId, {
    int retryIndex = 0,
  });

  Future<QuarkTransferTask> waitForTask(
    String taskId, {
    bool Function()? isCancelled,
  });

  Future<void> close();
}

class QuarkShareTransferService implements QuarkShareTransfer {
  QuarkShareTransferService({
    required QuarkShareApi api,
    QuarkTransferDelay? delay,
    this.maxTaskPolls = 40,
  })  : assert(maxTaskPolls > 0),
        _api = api,
        _delay = delay ?? Future<void>.delayed;

  static const int _pageSize = 50;
  static const int _maxPages = 200;

  final QuarkShareApi _api;
  final QuarkTransferDelay _delay;
  final int maxTaskPolls;
  final Map<String, String> _shareTokens = <String, String>{};

  @override
  Future<QuarkShareInspection> inspectShare(
    String shareUrl, {
    String? passcode,
  }) async {
    final parsed = _parseShareUrl(shareUrl);
    final token = await _api.getShareToken(
      shareId: parsed.shareId,
      passcode: passcode?.trim().isNotEmpty == true
          ? passcode!.trim()
          : parsed.passcode,
    );
    _shareTokens[parsed.shareId] = token;
    final entries = <QuarkShareEntry>[];
    final seen = <String>{};
    for (var page = 1; page <= _maxPages; page++) {
      final result = await _api.listSharePage(
        shareId: parsed.shareId,
        shareToken: token,
        directoryId: '0',
        page: page,
        size: _pageSize,
      );
      if (result.page != page || result.size <= 0 || result.total < 0) {
        throw const CloudDriveException(CloudDriveErrorType.incompatible);
      }
      for (final item in result.items) {
        if (!seen.add(item.id)) continue;
        final fileToken = item.shareFileToken;
        if (fileToken == null || fileToken.isEmpty) {
          throw const CloudDriveException(CloudDriveErrorType.incompatible);
        }
        entries.add(QuarkShareEntry(
          id: item.id,
          name: item.name,
          isDirectory: item.isDirectory,
          size: item.size,
          fileToken: fileToken,
        ));
      }
      if (result.items.isEmpty ||
          entries.length >= result.total ||
          page * result.size >= result.total) {
        return QuarkShareInspection(
          shareId: parsed.shareId,
          entries: List<QuarkShareEntry>.unmodifiable(entries),
        );
      }
    }
    throw const CloudDriveException(CloudDriveErrorType.incompatible);
  }

  @override
  Future<String> saveShare({
    required String shareId,
    required List<QuarkShareEntry> entries,
    required String targetDirectoryId,
  }) async {
    final token = _shareTokens[shareId];
    if (token == null || entries.isEmpty || targetDirectoryId.isEmpty) {
      throw const CloudDriveException(CloudDriveErrorType.invalidAddress);
    }
    return _api.saveShare(
      shareId: shareId,
      shareToken: token,
      fileIds: entries.map((entry) => entry.id).toList(growable: false),
      fileTokens:
          entries.map((entry) => entry.fileToken).toList(growable: false),
      targetDirectoryId: targetDirectoryId,
    );
  }

  @override
  Future<QuarkTransferTask> queryTask(
    String taskId, {
    int retryIndex = 0,
  }) =>
      _api.queryTask(taskId: taskId, retryIndex: retryIndex);

  @override
  Future<QuarkTransferTask> waitForTask(
    String taskId, {
    bool Function()? isCancelled,
  }) async {
    for (var retryIndex = 0; retryIndex < maxTaskPolls; retryIndex++) {
      if (isCancelled?.call() == true) {
        throw const CloudDriveException(CloudDriveErrorType.cancelled);
      }
      final task = await queryTask(taskId, retryIndex: retryIndex);
      switch (task.status) {
        case QuarkTransferTaskStatus.succeeded:
          return task;
        case QuarkTransferTaskStatus.failed:
          throw const CloudDriveException(CloudDriveErrorType.taskFailed);
        case QuarkTransferTaskStatus.cancelled:
          throw const CloudDriveException(CloudDriveErrorType.cancelled);
        case QuarkTransferTaskStatus.pending:
          if (retryIndex + 1 < maxTaskPolls) {
            await _delay(Duration(
              milliseconds: 500 * (1 << retryIndex.clamp(0, 3)),
            ));
          }
      }
    }
    throw const CloudDriveException(CloudDriveErrorType.taskTimeout);
  }

  @override
  Future<void> close() {
    _shareTokens.clear();
    return _api.close();
  }

  static ({String shareId, String passcode}) _parseShareUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'pan.quark.cn' ||
        uri.pathSegments.length < 2 ||
        uri.pathSegments.first != 's' ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(uri.pathSegments[1])) {
      throw const CloudDriveException(CloudDriveErrorType.invalidAddress);
    }
    return (
      shareId: uri.pathSegments[1],
      passcode: uri.queryParameters['pwd']?.trim() ?? '',
    );
  }
}
