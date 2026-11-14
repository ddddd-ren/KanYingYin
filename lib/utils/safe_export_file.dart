import 'dart:io';

import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;

class ExportFileRestoreException extends FileSystemException {
  ExportFileRestoreException(String backupPath)
      : super('保存失败，旧备份无法恢复到原位置，已保留在：$backupPath', backupPath);
}

/// 先完整生成导出文件，再保留旧文件并替换；失败时恢复旧文件。
Future<File> writeExportFileSafely(
  File output,
  Future<void> Function(File temporary) write,
) async {
  await output.parent.create(recursive: true);
  final staging = await output.parent.createTemp('.kyy-export-');
  final temporary = File('${staging.path}/new');
  final previous = File('${staging.path}/${p.basename(output.path)}.previous');
  var retainBackup = false;
  try {
    await write(temporary);
    if (await output.exists()) await output.rename(previous.path);
    try {
      await temporary.rename(output.path);
    } catch (_) {
      if (await previous.exists()) {
        try {
          await previous.rename(output.path);
        } catch (_) {
          retainBackup = true;
          throw ExportFileRestoreException(previous.path);
        }
      }
      rethrow;
    }
    return output;
  } finally {
    if (!retainBackup) {
      try {
        await staging.delete(recursive: true);
      } catch (error, stackTrace) {
        AppLogger().w('导出临时目录清理失败', error: error, stackTrace: stackTrace);
      }
    }
  }
}
