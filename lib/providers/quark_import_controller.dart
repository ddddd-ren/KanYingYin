import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_import_record.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_share_entry.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_transfer_task.dart';
import 'package:kanyingyin/repositories/quark_import_history_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_share_transfer_service.dart';

typedef QuarkSourceScanner = Future<void> Function(String sourceId);
typedef QuarkLibraryRefresher = Future<void> Function();

class QuarkDuplicateImportException implements Exception {
  const QuarkDuplicateImportException(this.idempotencyKey);
  final String idempotencyKey;
}

class QuarkImportController extends ChangeNotifier {
  QuarkImportController({
    required QuarkImportHistoryRepository historyRepository,
    required QuarkShareTransfer transferService,
    required QuarkSourceScanner scanSource,
    required QuarkLibraryRefresher refreshLibrary,
  })  : _historyRepository = historyRepository,
        _transferService = transferService,
        _scanSource = scanSource,
        _refreshLibrary = refreshLibrary;

  final QuarkImportHistoryRepository _historyRepository;
  final QuarkShareTransfer _transferService;
  final QuarkSourceScanner _scanSource;
  final QuarkLibraryRefresher _refreshLibrary;

  bool busy = false;
  String? errorMessage;

  Future<QuarkTransferTask> importEntry({
    required String sourceId,
    required String shareId,
    required QuarkShareEntry entry,
    required String targetDirectoryId,
  }) async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    final now = DateTime.now().toUtc();
    var record = QuarkImportRecord(
      sourceId: sourceId,
      shareId: shareId,
      sharedFileId: entry.id,
      targetDirectoryId: targetDirectoryId,
      displayName: entry.name,
      status: QuarkImportStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
    var claimed = false;
    try {
      claimed = await _historyRepository.tryBegin(record);
      if (!claimed) {
        throw QuarkDuplicateImportException(record.idempotencyKey);
      }
      final taskId = await _transferService.saveShare(
        shareId: shareId,
        entries: <QuarkShareEntry>[entry],
        targetDirectoryId: targetDirectoryId,
      );
      record =
          record.copyWith(taskId: taskId, updatedAt: DateTime.now().toUtc());
      await _historyRepository.save(record);
      final task = await _transferService.waitForTask(taskId);
      record = record.copyWith(
        status: QuarkImportStatus.succeeded,
        updatedAt: DateTime.now().toUtc(),
      );
      await _historyRepository.save(record);
      await _scanSource(sourceId);
      await _refreshLibrary();
      return task;
    } on CloudDriveException catch (error) {
      errorMessage = error.type.name;
      if (claimed) {
        record = record.copyWith(
          status: switch (error.type) {
            CloudDriveErrorType.taskTimeout => QuarkImportStatus.timedOut,
            CloudDriveErrorType.cancelled => QuarkImportStatus.cancelled,
            _ => QuarkImportStatus.failed,
          },
          updatedAt: DateTime.now().toUtc(),
        );
        await _historyRepository.save(record);
      }
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
