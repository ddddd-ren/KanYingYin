import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kanyingyin/utils/logger.dart';

abstract interface class TmdbCredentialStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

class SecureTmdbCredentialStore implements TmdbCredentialStore {
  SecureTmdbCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String key = 'kanyingyin_tmdb_credential_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: key);
}

class MemoryTmdbCredentialStore implements TmdbCredentialStore {
  MemoryTmdbCredentialStore([this._value]);

  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }

  @override
  Future<void> delete() async {
    _value = null;
  }
}

typedef LegacyTmdbCredentialReader = String Function();
typedef LegacyTmdbCredentialDelete = Future<void> Function();
typedef TmdbCredentialWarningLogger = void Function(String message);

class TmdbCredentialManager {
  TmdbCredentialManager({
    required TmdbCredentialStore store,
    required LegacyTmdbCredentialReader legacyReader,
    required LegacyTmdbCredentialDelete legacyDelete,
    TmdbCredentialWarningLogger? warningLogger,
  })  : _store = store,
        _legacyReader = legacyReader,
        _legacyDelete = legacyDelete,
        _warningLogger = warningLogger ?? AppLogger().w;

  final TmdbCredentialStore _store;
  final LegacyTmdbCredentialReader _legacyReader;
  final LegacyTmdbCredentialDelete _legacyDelete;
  final TmdbCredentialWarningLogger _warningLogger;
  String _current = '';

  String read() => _current;

  Future<void> initialize() async {
    final legacy = _readLegacy();
    try {
      final secureValue = (await _store.read())?.trim() ?? '';
      if (secureValue.isNotEmpty) {
        _current = secureValue;
        await _deleteLegacySafely();
        return;
      }
    } on Object {
      _current = legacy;
      _warningLogger('TMDB 凭据安全存储读取失败，继续使用兼容值');
      return;
    }

    if (legacy.isEmpty) return;
    _current = legacy;
    try {
      await _store.write(legacy);
      await _legacyDelete();
    } on Object {
      _warningLogger('TMDB 旧凭据迁移失败，已保留兼容值');
    }
  }

  Future<void> save(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await _store.delete();
      await _legacyDelete();
      _current = '';
      return;
    }

    await _store.write(normalized);
    _current = normalized;
    await _deleteLegacySafely();
  }

  String _readLegacy() {
    try {
      return _legacyReader().trim();
    } on Object {
      return '';
    }
  }

  Future<void> _deleteLegacySafely() async {
    try {
      await _legacyDelete();
    } on Object {
      _warningLogger('TMDB 旧凭据清理失败，将在下次启动重试');
    }
  }
}
