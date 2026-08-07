import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:kanyingyin/features/tv_preload/domain/tv_preload_manifest.dart';

final class PreloadValidationResult {
  const PreloadValidationResult({
    required this.configurationBytes,
    required this.metadataBytes,
    required this.configurationSha256,
    required this.metadataSha256,
  });

  final int configurationBytes;
  final int metadataBytes;
  final String configurationSha256;
  final String metadataSha256;
}

final class PreloadValidationException implements Exception {
  const PreloadValidationException(this.code);

  final String code;

  @override
  String toString() => 'PreloadValidationException($code)';
}

Future<PreloadValidationResult> validatePreloadFiles({
  required File configuration,
  required File metadata,
  required String password,
}) async {
  final configurationBytes = await _validateInput(
    configuration,
    extension: '.kyyconfig',
    maximumBytes: TvPreloadManifest.maxConfigurationBytes,
  );
  final metadataBytes = await _validateInput(
    metadata,
    extension: '.kyymeta',
    maximumBytes: TvPreloadManifest.maxMetadataBytes,
  );
  if (password.length < 8) {
    throw const PreloadValidationException('invalid_password');
  }
  await _validateConfiguration(configuration, password);
  await _validateMetadata(metadata);
  return PreloadValidationResult(
    configurationBytes: configurationBytes,
    metadataBytes: metadataBytes,
    configurationSha256: await _fileSha256(configuration),
    metadataSha256: await _fileSha256(metadata),
  );
}

Future<int> _validateInput(
  File file, {
  required String extension,
  required int maximumBytes,
}) async {
  if (!file.path.toLowerCase().endsWith(extension) || !await file.exists()) {
    throw const PreloadValidationException('invalid_input');
  }
  final length = await file.length();
  if (length <= 0 || length > maximumBytes) {
    throw const PreloadValidationException('invalid_size');
  }
  return length;
}

Future<void> _validateConfiguration(File file, String password) async {
  try {
    final envelope = _jsonMap(jsonDecode(await file.readAsString()));
    if (envelope['format'] != 'kyy-config' ||
        envelope['envelopeVersion'] != 1) {
      throw const FormatException();
    }
    final kdf = _jsonMap(envelope['kdf']);
    final cipher = _jsonMap(envelope['cipher']);
    if (kdf['name'] != 'pbkdf2-hmac-sha256' ||
        kdf['iterations'] != 600000 ||
        cipher['name'] != 'aes-256-gcm') {
      throw const FormatException();
    }
    final salt = base64Decode(kdf['salt'] as String);
    final nonce = base64Decode(cipher['nonce'] as String);
    final ciphertext = base64Decode(cipher['ciphertext'] as String);
    final mac = base64Decode(cipher['mac'] as String);
    if (salt.length != 16 ||
        nonce.length != 12 ||
        ciphertext.isEmpty ||
        mac.length != 16) {
      throw const FormatException();
    }
    final key = await Pbkdf2.hmacSha256(
      iterations: 600000,
      bits: 256,
    ).deriveKeyFromPassword(password: password, nonce: salt);
    final cleartext = await AesGcm.with256bits().decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    final configuration = _jsonMap(jsonDecode(utf8.decode(cleartext)));
    if (configuration['formatVersion'] != 1 ||
        configuration['exportedAt'] is! String ||
        configuration['appVersion'] is! String ||
        configuration['tmdbApiKey'] is! String ||
        configuration['cloudSources'] is! List<Object?>) {
      throw const FormatException();
    }
  } on PreloadValidationException {
    rethrow;
  } on Object {
    throw const PreloadValidationException('invalid_configuration');
  }
}

Future<void> _validateMetadata(File file) async {
  try {
    final archive = ZipDecoder().decodeBytes(
      await file.readAsBytes(),
      verify: true,
    );
    if (archive.files.isEmpty || archive.files.length > 20003) {
      throw const FormatException();
    }
    final files = <String, Uint8List>{};
    final archivePaths = <String>{};
    final archiveFilePaths = <String>{};
    for (final entry in archive.files) {
      final name = entry.name.replaceAll('\\', '/');
      final normalizedName = name.toLowerCase();
      if (!_safeArchivePath(entry.name) ||
          entry.isSymbolicLink ||
          !archivePaths.add(normalizedName)) {
        throw const FormatException();
      }
      if (!entry.isFile) continue;
      archiveFilePaths.add(name);
      files[normalizedName] = Uint8List.fromList(
        entry.content as List<int>,
      );
    }
    if (!archiveFilePaths.containsAll(<String>{
      'manifest.json',
      'local.json',
      'cloud.json',
    })) {
      throw const FormatException();
    }
    final manifestBytes = files['manifest.json'];
    final localBytes = files['local.json'];
    final cloudBytes = files['cloud.json'];
    if (manifestBytes == null || localBytes == null || cloudBytes == null) {
      throw const FormatException();
    }
    final manifest = _jsonMap(jsonDecode(utf8.decode(manifestBytes)));
    if (manifest['format'] != 'kanyingyin-scraped-metadata' ||
        manifest['formatVersion'] != 1 ||
        manifest['files'] is! List<Object?>) {
      throw const FormatException();
    }
    final declaredPaths = <String>{};
    final normalizedDeclaredPaths = <String>{};
    for (final value in manifest['files'] as List<Object?>) {
      final item = _jsonMap(value);
      final path = item['path'];
      final length = item['length'];
      final expectedHash = item['sha256'];
      if (path is! String ||
          length is! int ||
          expectedHash is! String ||
          !_safeArchivePath(path)) {
        throw const FormatException();
      }
      final normalizedPath = path.toLowerCase();
      if (!normalizedDeclaredPaths.add(normalizedPath)) {
        throw const FormatException();
      }
      declaredPaths.add(path);
      final content = files[normalizedPath];
      if (content == null ||
          content.length != length ||
          sha256.convert(content).toString() != expectedHash) {
        throw const FormatException();
      }
    }
    if (!declaredPaths.containsAll(<String>['local.json', 'cloud.json'])) {
      throw const FormatException();
    }
    final local = _jsonMap(jsonDecode(utf8.decode(localBytes)));
    final cloud = _jsonMap(jsonDecode(utf8.decode(cloudBytes)));
    if (local['localSources'] is! List<Object?> ||
        cloud['cloudSources'] is! List<Object?>) {
      throw const FormatException();
    }
  } on Object {
    throw const PreloadValidationException('invalid_metadata');
  }
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is! Map<Object?, Object?>) throw const FormatException();
  return Map<String, Object?>.from(value);
}

bool _safeArchivePath(String value) {
  if (value.isEmpty ||
      value.contains('\u0000') ||
      value.contains('\\') ||
      value.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value)) {
    return false;
  }
  final segments = value.split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

Future<String> _fileSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
