import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/app_update/application/windows_update_installer.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('app-update-file-');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('下载后校验大小和 SHA-256 并报告进度', () async {
    final bytes = utf8.encode('verified installer');
    final progress = <(int, int)>[];
    var downloads = 0;
    final installer = WindowsUpdateInstaller(
      directoryProvider: () async => tempDirectory,
      downloadFile: (_, target, onProgress) async {
        downloads++;
        await target.writeAsBytes(bytes);
        onProgress(bytes.length, bytes.length);
      },
    );

    final file = await installer.downloadAndVerify(
      _asset(bytes),
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(downloads, 1);
    expect(await file.readAsBytes(), bytes);
    expect(progress, <(int, int)>[(bytes.length, bytes.length)]);
  });

  test('已有文件校验通过时直接复用', () async {
    final bytes = utf8.encode('cached installer');
    final existing = File(p.join(tempDirectory.path, 'update.exe'));
    await existing.writeAsBytes(bytes);
    var downloads = 0;
    final installer = WindowsUpdateInstaller(
      directoryProvider: () async => tempDirectory,
      downloadFile: (_, __, ___) async => downloads++,
    );

    final file = await installer.downloadAndVerify(
      _asset(bytes, name: 'update.exe'),
    );

    expect(file.path, existing.path);
    expect(downloads, 0);
  });

  test('大小不符时删除下载文件', () async {
    final bytes = utf8.encode('short');
    final installer = WindowsUpdateInstaller(
      directoryProvider: () async => tempDirectory,
      downloadFile: (_, target, __) => target.writeAsBytes(bytes),
    );

    await expectLater(
      installer.downloadAndVerify(_asset(bytes, size: bytes.length + 1)),
      throwsA(isA<UpdatePackageVerificationException>()),
    );
    expect(
        await File(p.join(tempDirectory.path, 'update.exe')).exists(), false);
  });

  test('摘要不符时删除下载文件', () async {
    final bytes = utf8.encode('wrong digest');
    final installer = WindowsUpdateInstaller(
      directoryProvider: () async => tempDirectory,
      downloadFile: (_, target, __) => target.writeAsBytes(bytes),
    );

    await expectLater(
      installer.downloadAndVerify(
        _asset(
          bytes,
          sha256Value:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      throwsA(isA<UpdatePackageVerificationException>()),
    );
    expect(
        await File(p.join(tempDirectory.path, 'update.exe')).exists(), false);
  });

  test('安装器启动成功后退出应用', () async {
    var launchedPath = '';
    int? exitCode;
    final installer = WindowsUpdateInstaller(
      startProcess: (path) async => launchedPath = path,
      exitApplication: (code) => exitCode = code,
    );
    final file = File(p.join(tempDirectory.path, 'update.exe'));

    await installer.launchAndExit(file);

    expect(launchedPath, file.path);
    expect(exitCode, 0);
  });

  test('安装器启动失败时不退出应用', () async {
    var exited = false;
    final installer = WindowsUpdateInstaller(
      startProcess: (_) async => throw const ProcessException('update.exe', []),
      exitApplication: (_) => exited = true,
    );

    await expectLater(
      installer.launchAndExit(File(p.join(tempDirectory.path, 'update.exe'))),
      throwsA(isA<ProcessException>()),
    );
    expect(exited, isFalse);
  });
}

AppReleaseAsset _asset(
  List<int> bytes, {
  String name = 'update.exe',
  int? size,
  String? sha256Value,
}) =>
    AppReleaseAsset(
      name: name,
      size: size ?? bytes.length,
      sha256: sha256Value ?? sha256.convert(bytes).toString(),
      downloadUri: Uri.parse('https://example.invalid/$name'),
    );
