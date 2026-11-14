import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/logger.dart';

/// 仅对已确认损坏的设置库恢复，打开失败不得直接删除用户数据。
Future<Box<Object?>> openSettingsBoxSafely({
  required File file,
  required Future<Box<Object?>> Function() open,
}) async {
  // Hive 会在原库存在时删除压缩副本；中断后两者都保留，避免猜错恢复来源。
  if (await file.exists() && await File('${file.path}c').exists()) {
    throw FileSystemException(
      '检测到未完成的设置库压缩，原库和压缩副本均已保留，未自动重建。'
      '\n请先备份该目录，再检查并恢复 setting.hive 或 setting.hivec。'
      '\n设置库：${file.path}',
      file.path,
    );
  }
  try {
    return await open();
  } catch (error, stackTrace) {
    AppLogger().e('设置库打开失败', error: error, stackTrace: stackTrace);
    if (error is! HiveError ||
        error.message != 'Wrong checksum in hive file. Box may be corrupted.') {
      throw settingsOpenFailure(error, file.path);
    }
  }

  Directory? backupDirectory;
  try {
    final original = await file.readAsBytes();
    backupDirectory = await file.parent.createTemp('setting.recovery-');
    final backup = File('${backupDirectory.path}/setting.hive');
    await backup.writeAsBytes(original, flush: true);
    if (!listEquals(original, await backup.readAsBytes())) {
      throw const FileSystemException('设置库备份校验失败');
    }
    // 保留原文件本身，异常或中断后仍可从恢复目录取回。
    await file.rename('${backupDirectory.path}/setting.original.hive');
  } catch (error, stackTrace) {
    AppLogger().e('设置库备份失败', error: error, stackTrace: stackTrace);
    throw FileSystemException(
      '设置库损坏，但未能完成安全备份，已停止重建。请检查磁盘空间和目录权限。'
      '\n设置库：${file.path}'
      '${backupDirectory == null ? '' : '\n恢复目录：${backupDirectory.path}'}',
      file.path,
    );
  }

  try {
    final box = await open();
    AppLogger().w('设置已重置，原库保留在：${backupDirectory.path}');
    return box;
  } catch (error, stackTrace) {
    AppLogger().e('设置库重建失败', error: error, stackTrace: stackTrace);
    throw FileSystemException(
      '设置库重建失败，原数据已保留。请关闭其他看影音进程并检查目录权限后重试。'
      '\n恢复目录：${backupDirectory.path}',
      file.path,
    );
  }
}

FileSystemException settingsOpenFailure(Object error, String path) {
  final code = error is FileSystemException ? error.osError?.errorCode : null;
  final String reason;
  final isWindows = detectAppPlatform().isWindows;
  if (isWindows ? code == 5 : code == 13 || code == 1) {
    reason = '没有设置库的读写权限，请检查目录权限';
  } else if (isWindows
      ? code == 32 || code == 33
      : code == 11 || code == 16 || code == 35) {
    reason = '设置库正被占用，请关闭其他看影音进程后重试';
  } else {
    reason = '设置库打开失败，尚不能确认是文件损坏，请检查磁盘和目录是否可用';
  }
  return FileSystemException('$reason。未自动重建设置库。\n设置库：$path', path);
}
