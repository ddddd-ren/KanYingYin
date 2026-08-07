import 'dart:io';

import 'package:kanyingyin/features/tv_preload/application/tv_preload_import_ports.dart';
import 'package:kanyingyin/features/tv_preload/data/tv_preload_asset_reader.dart';
import 'package:kanyingyin/features/tv_preload/domain/tv_preload_manifest.dart';
import 'package:kanyingyin/platform/app_platform.dart';

final class TvPreloadImportService {
  TvPreloadImportService({
    required AppPlatformCapabilities capabilities,
    required TvPreloadAssetPort assets,
    required TvPreloadConfigurationPort configuration,
    required TvPreloadMetadataPort metadata,
    required TvPreloadMediaRefreshPort media,
    required TvPreloadStatePort state,
    String? password,
  })  : _capabilities = capabilities,
        _assets = assets,
        _configuration = configuration,
        _metadata = metadata,
        _media = media,
        _state = state,
        _password = password ?? compiledPassword;

  static const String compiledPassword =
      String.fromEnvironment('KYY_TV_PRELOAD_PASSWORD');

  final AppPlatformCapabilities _capabilities;
  final TvPreloadAssetPort _assets;
  final TvPreloadConfigurationPort _configuration;
  final TvPreloadMetadataPort _metadata;
  final TvPreloadMediaRefreshPort _media;
  final TvPreloadStatePort _state;
  final String _password;

  Future<TvPreloadImportResult> run() async {
    if (!_capabilities.isAndroidTv) {
      return const TvPreloadImportResult(
        status: TvPreloadImportStatus.skipped,
      );
    }

    TvPreloadManifest manifest;
    try {
      manifest = await _assets.readManifest();
    } on Object {
      await _state.writeFailure('manifest_read_failed');
      return const TvPreloadImportResult(
        status: TvPreloadImportStatus.failed,
        errorCode: 'manifest_read_failed',
      );
    }
    if (!manifest.enabled) {
      return const TvPreloadImportResult(
        status: TvPreloadImportStatus.skipped,
      );
    }
    if (_password.trim().isEmpty) {
      await _state.writeFailure('missing_password');
      return const TvPreloadImportResult(
        status: TvPreloadImportStatus.failed,
        errorCode: 'missing_password',
      );
    }

    final manifestHash =
        '${manifest.configurationSha256}:${manifest.metadataSha256}';
    if (_state.readManifestHash() == manifestHash) {
      return const TvPreloadImportResult(
        status: TvPreloadImportStatus.skipped,
      );
    }

    File? configurationFile;
    File? metadataFile;
    try {
      configurationFile = await _assets.copyVerifiedAsset(
        assetPath: manifest.configurationAsset!,
        expectedBytes: manifest.configurationBytes!,
        expectedSha256: manifest.configurationSha256!,
        fileName: 'configuration.kyyconfig',
      );
      final configurationSummary = await _configuration.importEncrypted(
        configurationFile,
        password: _password,
      );
      final mediaRefreshResult = await _media.loadAndScanEnabledSources();
      metadataFile = await _assets.copyVerifiedAsset(
        assetPath: manifest.metadataAsset!,
        expectedBytes: manifest.metadataBytes!,
        expectedSha256: manifest.metadataSha256!,
        fileName: 'metadata.kyymeta',
      );
      final metadataResult = await _metadata.importArchive(metadataFile);
      final status =
          mediaRefreshResult.failed > 0 || metadataResult.skippedCount > 0
              ? TvPreloadImportStatus.partial
              : TvPreloadImportStatus.success;
      final result = TvPreloadImportResult(
        status: status,
        configurationSummary: configurationSummary,
        metadataResult: metadataResult,
        mediaRefreshResult: mediaRefreshResult,
      );
      await _state.writeSuccess(manifestHash: manifestHash, result: result);
      return result;
    } on Object {
      await _state.writeFailure(_errorCode());
      return const TvPreloadImportResult(
        status: TvPreloadImportStatus.failed,
        errorCode: 'import_failed',
      );
    } finally {
      await _deleteTemporary(configurationFile);
      await _deleteTemporary(metadataFile);
    }
  }

  static Future<void> _deleteTemporary(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // 预置临时文件清理失败不覆盖导入结果。
    }
  }

  static String _errorCode() => 'import_failed';
}
