import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kanyingyin/core/network/dio_factory.dart';
import 'package:kanyingyin/core/network/network_config.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef UpdateDownloadProgress = void Function(int received, int total);
typedef UpdateDirectoryProvider = Future<Directory> Function();
typedef UpdateFileDownloader = Future<void> Function(
  Uri source,
  File target,
  UpdateDownloadProgress onProgress,
);
typedef UpdateProcessStarter = Future<void> Function(String path);
typedef UpdateApplicationExit = void Function(int code);

class UpdatePackageVerificationException implements Exception {
  const UpdatePackageVerificationException(this.message);

  final String message;

  @override
  String toString() => 'UpdatePackageVerificationException: $message';
}

class WindowsUpdateInstaller {
  WindowsUpdateInstaller({
    UpdateDirectoryProvider? directoryProvider,
    UpdateFileDownloader? downloadFile,
    UpdateProcessStarter? startProcess,
    UpdateApplicationExit? exitApplication,
  })  : _directoryProvider = directoryProvider ?? getTemporaryDirectory,
        _downloadFile = downloadFile ?? _downloadWithDio,
        _startProcess = startProcess ?? _startDetached,
        _exitApplication = exitApplication ?? exit;

  final UpdateDirectoryProvider _directoryProvider;
  final UpdateFileDownloader _downloadFile;
  final UpdateProcessStarter _startProcess;
  final UpdateApplicationExit _exitApplication;

  Future<File> downloadAndVerify(
    AppReleaseAsset asset, {
    UpdateDownloadProgress? onProgress,
  }) async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final safeName = p.basename(asset.name);
    if (safeName.isEmpty || safeName != asset.name) {
      throw const UpdatePackageVerificationException('安装包文件名无效');
    }
    final target = File(p.join(directory.path, safeName));
    if (await _matchesAsset(target, asset)) return target;
    await _deleteIfExists(target);

    try {
      await _downloadFile(
        asset.downloadUri,
        target,
        onProgress ?? (_, __) {},
      );
      if (!await _matchesAsset(target, asset)) {
        throw const UpdatePackageVerificationException('安装包大小或摘要不匹配');
      }
      return target;
    } on Object {
      await _deleteIfExists(target);
      rethrow;
    }
  }

  Future<void> launchAndExit(File installer) async {
    await _startProcess(installer.path);
    _exitApplication(0);
  }

  static Future<bool> _matchesAsset(
    File file,
    AppReleaseAsset asset,
  ) async {
    if (!await file.exists()) return false;
    if (await file.length() != asset.size) return false;
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == asset.sha256.toLowerCase();
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  static Future<void> _downloadWithDio(
    Uri source,
    File target,
    UpdateDownloadProgress onProgress,
  ) async {
    final dio = DioFactory.createForConfig(
      const NetworkConfig(
        connectTimeout: Duration(seconds: 15),
        receiveTimeout: Duration(minutes: 10),
      ),
      defaultHeaders: const <String, Object?>{
        'Accept': 'application/octet-stream',
        'User-Agent': 'KanYingYin-App-Updater',
      },
    );
    try {
      await dio.downloadUri(
        source,
        target.path,
        deleteOnError: true,
        onReceiveProgress: onProgress,
      );
    } finally {
      dio.close(force: true);
    }
  }

  static Future<void> _startDetached(String path) async {
    await Process.start(
      path,
      const <String>[],
      mode: ProcessStartMode.detached,
    );
  }
}
