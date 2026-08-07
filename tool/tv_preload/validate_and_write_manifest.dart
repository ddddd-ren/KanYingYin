import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/tv_preload/domain/tv_preload_manifest.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseOptions(arguments);
    final password = Platform.environment['KYY_CONFIG_PASSWORD'] ?? '';
    if (password.isEmpty) {
      throw const FormatException('missing_password');
    }
    final configuration = File(_required(options, 'configuration'));
    final metadata = File(_required(options, 'metadata'));
    final manifest = File(_required(options, 'manifest'));
    await _validateInput(
      configuration,
      extension: '.kyyconfig',
      maximumBytes: TvPreloadManifest.maxConfigurationBytes,
    );
    await _validateInput(
      metadata,
      extension: '.kyymeta',
      maximumBytes: TvPreloadManifest.maxMetadataBytes,
    );

    await ConfigurationArchiveCodec().decrypt(
      await configuration.readAsBytes(),
      password: password,
    );
    final metadataArchive = await ScrapedMetadataArchiveCodec(
      temporaryDirectoryProvider: () async => Directory.systemTemp,
    ).read(metadata);
    await metadataArchive.dispose();

    final configurationSha256 = await _fileSha256(configuration);
    final metadataSha256 = await _fileSha256(metadata);
    final output = TvPreloadManifest(
      enabled: true,
      version: TvPreloadManifest.currentVersion,
      configurationAsset: 'assets/tv_preload/configuration.kyyconfig',
      metadataAsset: 'assets/tv_preload/metadata.kyymeta',
      configurationBytes: await configuration.length(),
      metadataBytes: await metadata.length(),
      configurationSha256: configurationSha256,
      metadataSha256: metadataSha256,
    );
    await manifest.writeAsString(
      jsonEncode(output.toJson()),
      encoding: utf8,
      flush: true,
    );
    stdout.writeln('TV preload manifest validated');
  } on Object catch (error) {
    stderr.writeln('TV preload validation failed: ${error.runtimeType}');
    exitCode = 1;
  }
}

Map<String, String> _parseOptions(List<String> arguments) {
  if (arguments.length.isOdd) throw const FormatException('invalid_options');
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final name = arguments[index];
    if (!name.startsWith('--') || arguments[index + 1].trim().isEmpty) {
      throw const FormatException('invalid_options');
    }
    result[name.substring(2)] = arguments[index + 1];
  }
  return result;
}

String _required(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.trim().isEmpty) {
    throw FormatException('missing_$name');
  }
  return value;
}

Future<void> _validateInput(
  File file, {
  required String extension,
  required int maximumBytes,
}) async {
  if (!file.path.toLowerCase().endsWith(extension) || !await file.exists()) {
    throw const FormatException('invalid_input');
  }
  final length = await file.length();
  if (length <= 0 || length > maximumBytes) {
    throw const FormatException('invalid_size');
  }
}

Future<String> _fileSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
