import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_import_record.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_share_entry.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_transfer_task.dart';
import 'package:kanyingyin/repositories/quark_import_history_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/quark/quark_share_transfer_service.dart';

typedef QuarkSourceRefresher = Future<void> Function(String sourceId);
typedef QuarkSourceScanner = Future<void> Function(String sourceId);
typedef QuarkLibraryRefresher = Future<void> Function();

class QuarkDuplicateImportException implements Exception {
  const QuarkDuplicateImportException(this.idempotencyKey);
  final String idempotencyKey;
}

class QuarkImportBatchResult {
  const QuarkImportBatchResult({
    required this.task,
    this.refreshError,
  });

  final QuarkTransferTask task;
  final Object? refreshError;

  bool get libraryRefreshed => refreshError == null;
}

class QuarkImportController extends ChangeNotifier {
  QuarkImportController({
    required QuarkImportHistoryRepository historyRepository,
    required QuarkShareTransfer transferService,
    QuarkSourceRefresher? refreshSource,
    QuarkSourceScanner? scanSource,
    QuarkLibraryRefresher? refreshLibrary,
  })  : _historyRepository = historyRepository,
        _transferService = transferService,
        assert(
          refreshSource != null ||
              (scanSource != null && refreshLibrary != null),
        ),
        _refreshSource = refreshSource ??
            ((sourceId) async {
              await scanSource!(sourceId);
              await refreshLibrary!();
            });

  final QuarkImportHistoryRepository _historyRepository;
  final QuarkShareTransfer _transferService;
  final QuarkSourceRefresher _refreshSource;

  bool busy = false;
  String? errorMessage;

  Future<QuarkTransferTask> importEntry({
    required String sourceId,
    required String shareId,
    required QuarkShareEntry entry,
    required String targetDirectoryId,
  }) async {
    final result = await importEntries(
      sourceId: sourceId,
      shareId: shareId,
      entries: <QuarkShareEntry>[entry],
      targetDirectoryId: targetDirectoryId,
    );
    return result.task;
  }

  Future<QuarkImportBatchResult> importEntries({
    required String sourceId,
    required String shareId,
    required List<QuarkShareEntry> entries,
    required String targetDirectoryId,
  }) async {
    if (entries.isEmpty) {
      throw const CloudDriveException(CloudDriveErrorType.invalidAddress);
    }
    busy = true;
    errorMessage = null;
    notifyListeners();
    final now = DateTime.now().toUtc();
    var records = entries
        .map(
          (entry) => QuarkImportRecord(
            sourceId: sourceId,
            shareId: shareId,
            sharedFileId: entry.id,
            targetDirectoryId: targetDirectoryId,
            displayName: entry.name,
            status: QuarkImportStatus.pending,
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList(growable: false);
    var claimed = false;
    try {
      claimed = await _historyRepository.tryBeginAll(records);
      if (!claimed) {
        throw QuarkDuplicateImportException(records.first.idempotencyKey);
      }
      final taskId = await _transferService.saveShare(
        shareId: shareId,
        entries: entries,
        targetDirectoryId: targetDirectoryId,
      );
      records = records
          .map(
            (record) => record.copyWith(
              taskId: taskId,
              updatedAt: DateTime.now().toUtc(),
            ),
          )
          .toList(growable: false);
      await _historyRepository.saveAll(records);
      final task = await _transferService.waitForTask(taskId);
      records = records
          .map(
            (record) => record.copyWith(
              status: QuarkImportStatus.succeeded,
              updatedAt: DateTime.now().toUtc(),
            ),
          )
          .toList(growable: false);
      await _historyRepository.saveAll(records);
      Object? refreshError;
      try {
        await _refreshSource(sourceId);
      } on Object catch (error) {
        refreshError = error;
      }
      return QuarkImportBatchResult(
        task: task,
        refreshError: refreshError,
      );
    } on CloudDriveException catch (error) {
      errorMessage = error.type.name;
      if (claimed) {
        records = records
            .map(
              (record) => record.copyWith(
                status: switch (error.type) {
                  CloudDriveErrorType.taskTimeout => QuarkImportStatus.timedOut,
                  CloudDriveErrorType.cancelled => QuarkImportStatus.cancelled,
                  _ => QuarkImportStatus.failed,
                },
                updatedAt: DateTime.now().toUtc(),
              ),
            )
            .toList(growable: false);
        await _historyRepository.saveAll(records);
      }
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
