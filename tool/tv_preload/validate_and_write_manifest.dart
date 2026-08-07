import 'dart:convert';
import 'dart:io';

import 'package:kanyingyin/features/tv_preload/domain/tv_preload_manifest.dart';

import 'preload_validator.dart';

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
    final validation = await validatePreloadFiles(
      configuration: configuration,
      metadata: metadata,
      password: password,
    );
    final output = TvPreloadManifest(
      enabled: true,
      version: TvPreloadManifest.currentVersion,
      configurationAsset: 'assets/tv_preload/configuration.kyyconfig',
      metadataAsset: 'assets/tv_preload/metadata.kyymeta',
      configurationBytes: validation.configurationBytes,
      metadataBytes: validation.metadataBytes,
      configurationSha256: validation.configurationSha256,
      metadataSha256: validation.metadataSha256,
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
