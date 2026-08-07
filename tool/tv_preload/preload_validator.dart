import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/features/tv_preload/domain/tv_preload_manifest.dart';

const int _maxMetadataEntries = maxTransferImages + 3;
const int _maxMetadataImageBytes = 25 * 1024 * 1024;
const int _maxMetadataJsonBytes = 256 * 1024 * 1024;
const int _maxMetadataExtractedBytes = 10 * 1024 * 1024 * 1024;
const int _maxConfigurationCloudSources = 100;

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
    _validatePortableConfiguration(configuration);
  } on PreloadValidationException {
    rethrow;
  } on Object {
    throw const PreloadValidationException('invalid_configuration');
  }
}

Future<void> _validateMetadata(File file) async {
  InputFileStream? inputStream;
  Archive? archive;
  try {
    inputStream = InputFileStream(file.path);
    archive = ZipDecoder().decodeStream(inputStream, verify: true);
    if (archive.files.isEmpty || archive.files.length > _maxMetadataEntries) {
      throw const FormatException();
    }
    final files = <String, ArchiveFile>{};
    final archivePaths = <String>{};
    final archiveFilePaths = <String>{};
    var extractedBytes = 0;
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
      files[normalizedName] = entry;
      extractedBytes += entry.size;
      if (entry.size < 0 || extractedBytes > _maxMetadataExtractedBytes) {
        throw const FormatException();
      }
      if (name.startsWith('images/') && entry.size > _maxMetadataImageBytes) {
        throw const FormatException();
      }
      if ((name == 'manifest.json' ||
              name == 'local.json' ||
              name == 'cloud.json') &&
          entry.size > _maxMetadataJsonBytes) {
        throw const FormatException();
      }
    }
    if (!archiveFilePaths.containsAll(<String>{
      'manifest.json',
      'local.json',
      'cloud.json',
    })) {
      throw const FormatException();
    }
    final manifestEntry = files['manifest.json'];
    if (manifestEntry == null) {
      throw const FormatException();
    }
    final manifest = _readArchiveJson(manifestEntry);
    if (manifest['format'] != scrapedMetadataFormat ||
        manifest['formatVersion'] != scrapedMetadataFormatVersion ||
        manifest['files'] is! List<Object?>) {
      throw const FormatException();
    }
    final declaredPaths = <String>{};
    final normalizedDeclaredPaths = <String>{};
    Map<String, Object?>? local;
    Map<String, Object?>? cloud;
    for (final value in manifest['files'] as List<Object?>) {
      final item = _jsonMap(value);
      final path = item['path'];
      final length = item['length'];
      final expectedHash = item['sha256'];
      if (path is! String ||
          length is! int ||
          length < 0 ||
          expectedHash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash) ||
          !_safeArchivePath(path) ||
          (path != 'local.json' &&
              path != 'cloud.json' &&
              !path.startsWith('images/'))) {
        throw const FormatException();
      }
      final normalizedPath = path.toLowerCase();
      if (!normalizedDeclaredPaths.add(normalizedPath)) {
        throw const FormatException();
      }
      declaredPaths.add(path);
      final entry = files[normalizedPath];
      if (entry == null ||
          entry.name.replaceAll('\\', '/') != path ||
          entry.size != length) {
        throw const FormatException();
      }
      final content = _readArchiveBytes(entry);
      try {
        if (sha256.convert(content).toString() != expectedHash) {
          throw const FormatException();
        }
        if (path == 'local.json') {
          local = _jsonMap(jsonDecode(utf8.decode(content)));
        } else if (path == 'cloud.json') {
          cloud = _jsonMap(jsonDecode(utf8.decode(content)));
        }
      } finally {
        entry.clear();
      }
    }
    if (!declaredPaths.containsAll(<String>['local.json', 'cloud.json']) ||
        local == null ||
        cloud == null) {
      throw const FormatException();
    }
    ScrapedMetadataPayload.fromJson(<String, Object?>{
      'formatVersion': manifest['formatVersion'],
      'exportedAt': manifest['exportedAt'],
      'appVersion': manifest['appVersion'],
      'localSources': local['localSources'],
      'cloudSources': cloud['cloudSources'],
    });
  } on Object {
    throw const PreloadValidationException('invalid_metadata');
  } finally {
    await archive?.clear();
    await inputStream?.close();
  }
}

Uint8List _readArchiveBytes(ArchiveFile entry) {
  final bytes = entry.readBytes();
  if (bytes == null || bytes.length != entry.size) {
    throw const FormatException();
  }
  return bytes;
}

Map<String, Object?> _readArchiveJson(ArchiveFile entry) {
  final bytes = _readArchiveBytes(entry);
  try {
    return _jsonMap(jsonDecode(utf8.decode(bytes)));
  } finally {
    entry.clear();
  }
}

void _validatePortableConfiguration(Map<String, Object?> configuration) {
  final exportedAt = configuration['exportedAt'];
  final appVersion = configuration['appVersion'];
  final tmdbApiKey = configuration['tmdbApiKey'];
  final cloudSources = configuration['cloudSources'];
  if (configuration['formatVersion'] != 1 ||
      exportedAt is! String ||
      DateTime.tryParse(exportedAt) == null ||
      appVersion is! String ||
      appVersion.trim().isEmpty ||
      appVersion.length > 80 ||
      tmdbApiKey is! String ||
      tmdbApiKey.length > 16384 ||
      cloudSources is! List<Object?> ||
      cloudSources.length > _maxConfigurationCloudSources) {
    throw const FormatException();
  }

  final sourceIds = <String>{};
  for (final value in cloudSources) {
    final portableSource = _jsonMap(value);
    final source = _jsonMap(portableSource['source']);
    final credential = portableSource['credential'];
    if (credential != null && credential is! Map<Object?, Object?>) {
      throw const FormatException();
    }
    final sourceId = _validatePortableCloudSource(source);
    if (!sourceIds.add(sourceId)) {
      throw const FormatException();
    }
  }
}

String _validatePortableCloudSource(Map<String, Object?> source) {
  final idValue = source['id'];
  final typeValue = source['type'];
  final nameValue = source['name'];
  final baseUrlValue = source['baseUrl'];
  if (idValue is! String ||
      typeValue is! String ||
      nameValue is! String ||
      baseUrlValue is! String) {
    throw const FormatException();
  }
  final id = idValue.trim();
  final name = nameValue.trim();
  final baseUrl = baseUrlValue.trim();
  if (id.isEmpty || id.length > 128 || name.isEmpty || name.length > 120) {
    throw const FormatException();
  }
  const sourceTypes = <String>{'openList', 'quark', 'baidu', 'xunlei'};
  if (!sourceTypes.contains(typeValue)) {
    throw const FormatException();
  }
  final uri = Uri.tryParse(baseUrl);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException();
  }
  final fixedUrl = switch (typeValue) {
    'quark' => 'https://pan.quark.cn',
    'baidu' => 'https://pan.baidu.com',
    'xunlei' => 'https://pan.xunlei.com',
    _ => null,
  };
  if (fixedUrl != null && baseUrl != fixedUrl) {
    throw const FormatException();
  }

  final rootPaths = _optionalList(source['rootPaths']);
  if (rootPaths.length > 64) {
    throw const FormatException();
  }
  for (final value in rootPaths) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.trim().length > 1024) {
      throw const FormatException();
    }
  }
  final rootRefs = _optionalList(source['rootRefs']);
  if (rootRefs.length > 64) {
    throw const FormatException();
  }
  for (final value in rootRefs) {
    _validateRemoteRef(_jsonMap(value));
  }
  final defaultTransferDirectory = source['defaultTransferDirectory'];
  if (defaultTransferDirectory != null) {
    _validateRemoteRef(_jsonMap(defaultTransferDirectory));
  }
  return id;
}

List<Object?> _optionalList(Object? value) {
  if (value == null) return const <Object?>[];
  if (value is! List<Object?>) throw const FormatException();
  return value;
}

void _validateRemoteRef(Map<String, Object?> value) {
  final id = value['id'];
  final path = value['path'];
  if (id is! String ||
      path is! String ||
      id.length > 2048 ||
      path.length > 2048) {
    throw const FormatException();
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
