import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/quark/quark_import_record.dart';
import 'package:kanyingyin/repositories/quark_import_history_repository.dart';

void main() {
  test('四字段组成稳定幂等键且持久化不含敏感信息', () async {
    final repository = QuarkImportHistoryRepository(
      storage: MemoryQuarkImportHistoryStorage(),
    );
    final record = QuarkImportRecord(
      sourceId: 'source-fixture',
      shareId: 'share-fixture',
      sharedFileId: 'file-fixture',
      targetDirectoryId: 'target-fixture',
      displayName: '示例目录',
      status: QuarkImportStatus.pending,
      createdAt: DateTime.utc(2026, 7, 19),
      updatedAt: DateTime.utc(2026, 7, 19),
    );

    expect(record.idempotencyKey,
        'source-fixture|share-fixture|file-fixture|target-fixture');
    expect(await repository.tryBegin(record), isTrue);
    expect(await repository.tryBegin(record), isFalse);

    final exported = await repository.exportJson();
    final decoded = jsonDecode(exported) as List<Object?>;
    expect(decoded, hasLength(1));
    for (final forbidden in <String>[
      'cookie',
      'stoken',
      'download_url',
      'headers',
    ]) {
      expect(exported.toLowerCase(), isNot(contains(forbidden)));
    }
  });

  test('进行中和成功阻止重复，失败超时取消允许重新开始', () async {
    final repository = QuarkImportHistoryRepository(
      storage: MemoryQuarkImportHistoryStorage(),
    );
    final base = QuarkImportRecord(
      sourceId: 'source-fixture',
      shareId: 'share-fixture',
      sharedFileId: 'file-fixture',
      targetDirectoryId: 'target-fixture',
      displayName: '示例目录',
      status: QuarkImportStatus.pending,
      createdAt: DateTime.utc(2026, 7, 19),
      updatedAt: DateTime.utc(2026, 7, 19),
    );

    for (final blocked in <QuarkImportStatus>[
      QuarkImportStatus.pending,
      QuarkImportStatus.succeeded,
    ]) {
      await repository.save(base.copyWith(status: blocked));
      expect(await repository.tryBegin(base), isFalse);
    }
    for (final retryable in <QuarkImportStatus>[
      QuarkImportStatus.failed,
      QuarkImportStatus.timedOut,
      QuarkImportStatus.cancelled,
    ]) {
      await repository.save(base.copyWith(status: retryable));
      expect(await repository.tryBegin(base), isTrue);
    }
  });
}
