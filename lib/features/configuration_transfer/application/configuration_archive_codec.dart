import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';

final class ConfigurationArchiveCodec {
  ConfigurationArchiveCodec({Random? random})
      : _random = random ?? Random.secure();

  static const int maxEnvelopeBytes = 512 * 1024;
  static const int minimumPasswordLength = 8;
  static const int kdfIterations = 600000;
  static const int envelopeVersion = 1;

  final Random _random;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<Uint8List> encrypt(
    PortableAppConfiguration configuration, {
    required String password,
  }) async {
    _validatePassword(password);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final secretKey = await _deriveKey(password, salt);
    final cleartext = utf8.encode(jsonEncode(configuration.toJson()));
    final secretBox = await _cipher.encrypt(
      cleartext,
      secretKey: secretKey,
      nonce: nonce,
    );
    final envelope = <String, Object>{
      'format': 'kyy-config',
      'envelopeVersion': envelopeVersion,
      'kdf': <String, Object>{
        'name': 'pbkdf2-hmac-sha256',
        'iterations': kdfIterations,
        'salt': base64Encode(salt),
      },
      'cipher': <String, Object>{
        'name': 'aes-256-gcm',
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
      },
    };
    final encoded = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    if (encoded.length > maxEnvelopeBytes) {
      throw ConfigurationArchiveTooLargeException(encoded.length);
    }
    return encoded;
  }

  Future<PortableAppConfiguration> decrypt(
    Uint8List bytes, {
    required String password,
  }) async {
    _validatePassword(password);
    if (bytes.length > maxEnvelopeBytes) {
      throw ConfigurationArchiveTooLargeException(bytes.length);
    }

    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<Object?, Object?>) throw const FormatException();
      envelope = Map<String, dynamic>.from(decoded);
    } on Object {
      throw const ConfigurationArchiveFormatException('invalid_json');
    }

    if (envelope['format'] != 'kyy-config') {
      throw const ConfigurationArchiveFormatException('invalid_format');
    }
    if (envelope['envelopeVersion'] != envelopeVersion) {
      throw const ConfigurationArchiveUnsupportedVersionException();
    }
    final kdf = _objectMap(envelope['kdf']);
    final cipher = _objectMap(envelope['cipher']);
    if (kdf['name'] != 'pbkdf2-hmac-sha256' ||
        kdf['iterations'] != kdfIterations ||
        cipher['name'] != 'aes-256-gcm') {
      throw const ConfigurationArchiveFormatException(
        'unsupported_algorithm',
      );
    }

    try {
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
      final secretKey = await _deriveKey(password, salt);
      final cleartext = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
      );
      final decoded = jsonDecode(utf8.decode(cleartext));
      if (decoded is! Map<Object?, Object?>) throw const FormatException();
      return PortableAppConfiguration.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on SecretBoxAuthenticationError {
      throw const ConfigurationArchiveAuthenticationException();
    } on PortableConfigurationValidationException catch (error) {
      if (error.code == 'unsupported_format_version') {
        throw const ConfigurationArchiveUnsupportedVersionException();
      }
      rethrow;
    } on ConfigurationArchiveUnsupportedVersionException {
      rethrow;
    } on Object {
      throw const ConfigurationArchiveFormatException('invalid_envelope');
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt) =>
      Pbkdf2.hmacSha256(
        iterations: kdfIterations,
        bits: 256,
      ).deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );

  Uint8List _randomBytes(int length) => Uint8List.fromList(
        List<int>.generate(length, (_) => _random.nextInt(256)),
      );

  static Map<String, dynamic> _objectMap(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const ConfigurationArchiveFormatException('missing_section');
    }
    return Map<String, dynamic>.from(value);
  }

  static void _validatePassword(String password) {
    if (password.length < minimumPasswordLength) {
      throw const ConfigurationArchivePasswordException();
    }
  }
}

final class ConfigurationArchivePasswordException implements Exception {
  const ConfigurationArchivePasswordException();

  @override
  String toString() => 'ConfigurationArchivePasswordException';
}

final class ConfigurationArchiveAuthenticationException implements Exception {
  const ConfigurationArchiveAuthenticationException();

  @override
  String toString() => 'ConfigurationArchiveAuthenticationException';
}

final class ConfigurationArchiveUnsupportedVersionException
    implements Exception {
  const ConfigurationArchiveUnsupportedVersionException();

  @override
  String toString() => 'ConfigurationArchiveUnsupportedVersionException';
}

final class ConfigurationArchiveFormatException implements Exception {
  const ConfigurationArchiveFormatException(this.code);

  final String code;

  @override
  String toString() => 'ConfigurationArchiveFormatException($code)';
}

final class ConfigurationArchiveTooLargeException implements Exception {
  const ConfigurationArchiveTooLargeException(this.actualBytes);

  final int actualBytes;

  @override
  String toString() =>
      'ConfigurationArchiveTooLargeException(actualBytes: $actualBytes)';
}
