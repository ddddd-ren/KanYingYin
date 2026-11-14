import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TmdbVisionModelCredentialStore {
  Future<String> read();

  Future<void> save(String value);
}

class TmdbVisionModelCredentials implements TmdbVisionModelCredentialStore {
  TmdbVisionModelCredentials({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String key = 'kanyingyin_tmdb_vision_model_key_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String> read() async => (await _storage.read(key: key))?.trim() ?? '';

  @override
  Future<void> save(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: normalized);
    }
  }
}

class MemoryTmdbVisionModelCredentials
    implements TmdbVisionModelCredentialStore {
  MemoryTmdbVisionModelCredentials([this.value = '']);

  String value;

  @override
  Future<String> read() async => value;

  @override
  Future<void> save(String value) async {
    this.value = value.trim();
  }
}
