import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CloudCredential {
  const CloudCredential({
    this.username,
    this.password,
    this.cookie,
    this.token,
    this.clientId,
    this.clientSecret,
    this.accessToken,
    this.refreshToken,
    this.accessTokenExpiresAt,
  });

  final String? username;
  final String? password;
  final String? cookie;
  final String? token;
  final String? clientId;
  final String? clientSecret;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? accessTokenExpiresAt;

  bool get isEmpty =>
      (username?.isEmpty ?? true) &&
      (password?.isEmpty ?? true) &&
      (cookie?.isEmpty ?? true) &&
      (token?.isEmpty ?? true) &&
      (clientId?.isEmpty ?? true) &&
      (clientSecret?.isEmpty ?? true) &&
      (accessToken?.isEmpty ?? true) &&
      (refreshToken?.isEmpty ?? true) &&
      accessTokenExpiresAt == null;

  Map<String, String> toJson() => <String, String>{
        if (username != null) 'username': username!,
        if (password != null) 'password': password!,
        if (cookie != null) 'cookie': cookie!,
        if (token != null) 'token': token!,
        if (clientId != null) 'clientId': clientId!,
        if (clientSecret != null) 'clientSecret': clientSecret!,
        if (accessToken != null) 'accessToken': accessToken!,
        if (refreshToken != null) 'refreshToken': refreshToken!,
        if (accessTokenExpiresAt != null)
          'accessTokenExpiresAt': accessTokenExpiresAt!.toIso8601String(),
      };

  factory CloudCredential.fromJson(Map<String, dynamic> json) =>
      CloudCredential(
        username:
            json['username'] is String ? json['username'] as String : null,
        password:
            json['password'] is String ? json['password'] as String : null,
        cookie: json['cookie'] is String ? json['cookie'] as String : null,
        token: json['token'] is String ? json['token'] as String : null,
        clientId:
            json['clientId'] is String ? json['clientId'] as String : null,
        clientSecret: json['clientSecret'] is String
            ? json['clientSecret'] as String
            : null,
        accessToken: json['accessToken'] is String
            ? json['accessToken'] as String
            : null,
        refreshToken: json['refreshToken'] is String
            ? json['refreshToken'] as String
            : null,
        accessTokenExpiresAt: json['accessTokenExpiresAt'] is String
            ? DateTime.tryParse(json['accessTokenExpiresAt'] as String)?.toUtc()
            : null,
      );

  @override
  String toString() => 'CloudCredential(<redacted>)';
}

abstract interface class CloudCredentialStore {
  Future<CloudCredential?> read(String sourceId);

  Future<void> write(String sourceId, CloudCredential credential);

  Future<void> delete(String sourceId);
}

class CloudCredentialCorruptedException implements Exception {
  const CloudCredentialCorruptedException(this.sourceId);

  final String sourceId;

  @override
  String toString() => 'CloudCredentialCorruptedException(sourceId: $sourceId)';
}

abstract interface class SecureValueStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureValueStorage implements SecureValueStorage {
  FlutterSecureValueStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SecureCloudCredentialStore implements CloudCredentialStore {
  SecureCloudCredentialStore({
    SecureValueStorage? valueStorage,
    FlutterSecureStorage? storage,
  }) : _storage = valueStorage ?? FlutterSecureValueStorage(storage: storage);

  static const String _keyPrefix = 'cloud_source_credential_';
  final SecureValueStorage _storage;

  @override
  Future<CloudCredential?> read(String sourceId) async {
    final value = await _storage.read('$_keyPrefix$sourceId');
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) {
        throw const FormatException();
      }
      return CloudCredential.fromJson(Map<String, dynamic>.from(decoded));
    } on Object {
      throw CloudCredentialCorruptedException(sourceId);
    }
  }

  @override
  Future<void> write(String sourceId, CloudCredential credential) =>
      _storage.write(
        '$_keyPrefix$sourceId',
        jsonEncode(credential.toJson()),
      );

  @override
  Future<void> delete(String sourceId) =>
      _storage.delete('$_keyPrefix$sourceId');
}

class MemoryCloudCredentialStore implements CloudCredentialStore {
  final Map<String, CloudCredential> _credentials = <String, CloudCredential>{};

  @override
  Future<CloudCredential?> read(String sourceId) async =>
      _credentials[sourceId];

  @override
  Future<void> write(String sourceId, CloudCredential credential) async {
    _credentials[sourceId] = credential;
  }

  @override
  Future<void> delete(String sourceId) async {
    _credentials.remove(sourceId);
  }
}
