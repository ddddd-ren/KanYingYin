import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/settings_box_recovery.dart';

void main() {
  late Directory root;
  late File file;
  const damagedBytes = [1, 2, 3, 4, 5];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('settings-open-safety-');
    file = File('${root.path}/setting.hive');
    await file.writeAsBytes(damagedBytes, flush: true);
  });

  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('真实损坏库禁用隐式截断，完整备份并保留原文件后才重建', () async {
    var attempts = 0;
    final box = await openSettingsBoxSafely(
      file: file,
      open: () async {
        attempts++;
        if (attempts == 2) {
          expect(await file.exists(), isFalse);
          final recovery = root.listSync().whereType<Directory>().single;
          expect(await File('${recovery.path}/setting.hive').readAsBytes(),
              damagedBytes);
          expect(
              await File('${recovery.path}/setting.original.hive')
                  .readAsBytes(),
              damagedBytes);
        }
        return Hive.openBox<Object?>(
          'setting',
          path: root.path,
          crashRecovery: false,
        );
      },
    );
    expect(attempts, 2);
    expect(box.isEmpty, isTrue);
    await box.put('theme', 'dark');
    expect(box.get('theme'), 'dark');
  });

  test('中断压缩留下两个候选库时不让 Hive 删除任一候选', () async {
    final compacted = File('${file.path}c');
    await compacted.writeAsBytes([8, 7, 6], flush: true);
    var attempts = 0;
    await expectLater(
      openSettingsBoxSafely(
        file: file,
        open: () async {
          attempts++;
          return Hive.openBox<Object?>(
            'setting',
            path: root.path,
            crashRecovery: false,
          );
        },
      ),
      throwsA(isA<FileSystemException>()
          .having((e) => e.message, 'message', contains('压缩副本均已保留'))),
    );
    expect(attempts, 0);
    expect(await file.readAsBytes(), damagedBytes);
    expect(await compacted.readAsBytes(), [8, 7, 6]);
  });

  test('仅剩损坏压缩副本时先恢复文件名，再完整备份后重建', () async {
    await file.rename('${file.path}c');
    final box = await openSettingsBoxSafely(
      file: file,
      open: () => Hive.openBox<Object?>(
        'setting',
        path: root.path,
        crashRecovery: false,
      ),
    );
    expect(box.isEmpty, isTrue);
    final recovery = root.listSync().whereType<Directory>().single;
    expect(await File('${recovery.path}/setting.hive').readAsBytes(),
        damagedBytes);
    expect(await File('${recovery.path}/setting.original.hive').readAsBytes(),
        damagedBytes);
  });

  for (final code in [5, 32, 33, 112]) {
    test('文件系统错误 $code 不备份、不移动、不重建原库', () async {
      var attempts = 0;
      await expectLater(
        openSettingsBoxSafely(
          file: file,
          open: () async {
            attempts++;
            throw FileSystemException(
                'test failure', file.path, OSError('', code));
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(attempts, 1);
      expect(await file.readAsBytes(), damagedBytes);
      expect(root.listSync().whereType<Directory>(), isEmpty);
    });
  }

  test('未知 Hive 异常不误判损坏', () async {
    await expectLater(
      openSettingsBoxSafely(
        file: file,
        open: () async => throw HiveError('Cannot read, unknown typeId: 99'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await file.readAsBytes(), damagedBytes);
    expect(root.listSync().whereType<Directory>(), isEmpty);
  });

  test('备份目录创建失败时保留原库且禁止第二次打开', () async {
    var attempts = 0;
    await expectLater(
      openSettingsBoxSafely(
        file: _BackupFailureFile(file),
        open: () async {
          attempts++;
          throw _corruption();
        },
      ),
      throwsA(isA<FileSystemException>()
          .having((e) => e.message, 'message', contains('已停止重建'))),
    );
    expect(attempts, 1);
    expect(await file.readAsBytes(), damagedBytes);
  });

  test('备份后移动原库失败保留两份数据且禁止重建', () async {
    var attempts = 0;
    await expectLater(
      openSettingsBoxSafely(
        file: _MoveFailureFile(file),
        open: () async {
          attempts++;
          throw _corruption();
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(attempts, 1);
    expect(await file.readAsBytes(), damagedBytes);
    final recovery = root.listSync().whereType<Directory>().single;
    expect(await File('${recovery.path}/setting.hive').readAsBytes(),
        damagedBytes);
  });

  test('备份文件无法写入时不移动原库也不重建', () async {
    var attempts = 0;
    await expectLater(
      openSettingsBoxSafely(
        file: _WriteFailureFile(file),
        open: () async {
          attempts++;
          throw _corruption();
        },
      ),
      throwsA(isA<FileSystemException>()
          .having((e) => e.message, 'message', contains('已停止重建'))),
    );
    expect(attempts, 1);
    expect(await file.readAsBytes(), damagedBytes);
  });

  test('重建中断或异常后恢复目录仍保留全部原数据', () async {
    var attempts = 0;
    await expectLater(
      openSettingsBoxSafely(
        file: file,
        open: () async {
          if (++attempts == 1) throw _corruption();
          await file.writeAsBytes([9], flush: true);
          throw const FileSystemException('模拟重建中断');
        },
      ),
      throwsA(isA<FileSystemException>()
          .having((e) => e.message, 'message', contains('原数据已保留'))),
    );
    final recovery = root.listSync().whereType<Directory>().single;
    expect(await File('${recovery.path}/setting.hive').readAsBytes(),
        damagedBytes);
    expect(await File('${recovery.path}/setting.original.hive').readAsBytes(),
        damagedBytes);
  });

  test('权限、占用和未知错误采用不同提示', () {
    final permission = Platform.isWindows ? 5 : 13;
    final busy = Platform.isWindows ? 32 : 11;
    String message(int code) => settingsOpenFailure(
          FileSystemException('', '', OSError('', code)),
          file.path,
        ).message;
    expect(message(permission), contains('读写权限'));
    expect(message(busy), contains('被占用'));
    expect(message(999), contains('尚不能确认'));
  });
}

HiveError _corruption() =>
    HiveError('Wrong checksum in hive file. Box may be corrupted.');

class _BackupFailureFile extends Fake implements File {
  _BackupFailureFile(this.original);
  final File original;

  @override
  String get path => '${original.parent.path}/missing/setting.hive';

  @override
  Directory get parent => File(path).parent;

  @override
  Future<Uint8List> readAsBytes() => original.readAsBytes();

  @override
  Future<bool> exists() => original.exists();
}

class _MoveFailureFile extends _BackupFailureFile {
  _MoveFailureFile(super.original);

  @override
  String get path => original.path;

  @override
  Future<File> rename(String newPath) async =>
      throw const FileSystemException('模拟原文件被占用');
}

class _WriteFailureFile extends _BackupFailureFile {
  _WriteFailureFile(super.original);

  @override
  String get path => original.path;

  @override
  Directory get parent => _WriteFailureDirectory(original.parent);
}

class _WriteFailureDirectory extends Fake implements Directory {
  _WriteFailureDirectory(this.original);
  final Directory original;

  @override
  Future<Directory> createTemp([String? prefix]) async {
    final directory = await original.createTemp(prefix);
    await Directory('${directory.path}/setting.hive').create();
    return directory;
  }
}
