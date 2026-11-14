import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/safe_export_file.dart';

void main() {
  late Directory root;
  late File output;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('safe-export-test-');
    output = File('${root.path}/backup');
    await output.writeAsString('旧备份', flush: true);
  });
  tearDown(() => root.delete(recursive: true));

  test('完整写入后替换旧备份并清理临时文件', () async {
    await writeExportFileSafely(output, (temporary) async {
      await temporary.writeAsString('新备份', flush: true);
      expect(await output.readAsString(), '旧备份');
    });
    expect(await output.readAsString(), '新备份');
    expect(root.listSync(), hasLength(1));
  });

  test('写入中途失败不截断旧备份', () async {
    await expectLater(
      writeExportFileSafely(output, (temporary) async {
        await temporary.writeAsString('未完成', flush: true);
        throw const FileSystemException('模拟空间不足');
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(await output.readAsString(), '旧备份');
    expect(root.listSync(), hasLength(1));
  });

  test('提交失败恢复旧备份', () async {
    await expectLater(
      writeExportFileSafely(output, (temporary) async {
        // 模拟生成文件在提交前丢失，触发真实 rename 失败。
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(await output.readAsString(), '旧备份');
    expect(root.listSync(), hasLength(1));
  });

  test('旧备份恢复到原路径失败时仍保留原件并提供位置', () async {
    ExportFileRestoreException? failure;
    try {
      await writeExportFileSafely(_BlockedRestoreFile(output),
          (temporary) async {
        await temporary.writeAsString('新备份', flush: true);
      });
    } on ExportFileRestoreException catch (error) {
      failure = error;
    }
    expect(failure, isNotNull);
    expect(await File(failure!.path!).readAsString(), '旧备份');
    expect(failure.message, contains(failure.path!));
  });
}

class _BlockedRestoreFile extends Fake implements File {
  _BlockedRestoreFile(this.file);
  final File file;
  @override
  String get path => file.path;
  @override
  Directory get parent => file.parent;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<File> rename(String newPath) async {
    final result = await file.rename(newPath);
    await Directory(file.path).create();
    return result;
  }
}
