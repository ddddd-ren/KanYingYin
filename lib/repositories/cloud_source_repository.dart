import 'dart:convert';

import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class CloudSourceStorage {
  Object get synchronizationIdentity;

  Future<List<Map<String, dynamic>>> read();

  Future<void> write(List<Map<String, dynamic>> sources);
}

class HiveCloudSourceStorage implements CloudSourceStorage {
  static final Object _sharedSettingBoxIdentity = Object();

  @override
  Object get synchronizationIdentity => _sharedSettingBoxIdentity;

  @override
  Future<List<Map<String, dynamic>>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.cloudSources,
      defaultValue: const <Map<String, dynamic>>[],
    );
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  @override
  Future<void> write(List<Map<String, dynamic>> sources) =>
      GStorage.setting.put(SettingBoxKey.cloudSources, sources);
}

class MemoryCloudSourceStorage implements CloudSourceStorage {
  List<Map<String, dynamic>> _sources = <Map<String, dynamic>>[];

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, dynamic>>> read() async => _sources
      .map((source) => Map<String, dynamic>.from(source))
      .toList(growable: false);

  @override
  Future<void> write(List<Map<String, dynamic>> sources) async {
    _sources = sources
        .map((source) => Map<String, dynamic>.from(source))
        .toList(growable: false);
  }
}

class CloudSourceRepository {
  static final Expando<Lock> _storageLocks = Expando<Lock>();

  CloudSourceRepository({
    CloudSourceStorage? storage,
    CloudCredentialStore? credentialStore,
  })  : _storage = storage ?? HiveCloudSourceStorage(),
        _credentialStore = credentialStore ?? SecureCloudCredentialStore() {
    final identity = _storage.synchronizationIdentity;
    _mutationLock = _storageLocks[identity] ??= Lock();
  }

  final CloudSourceStorage _storage;
  final CloudCredentialStore _credentialStore;
  late final Lock _mutationLock;

  Future<List<CloudSource>> getAll() async {
    final sources = <CloudSource>[];
    for (final item in await _storage.read()) {
      try {
        final source = CloudSource.fromJson(item);
        if (source.id.isNotEmpty) sources.add(source);
      } on Object {
        continue;
      }
    }
    return sources;
  }

  Future<CloudSource?> getById(String sourceId) async {
    for (final source in await getAll()) {
      if (source.id == sourceId) return source;
    }
    return null;
  }

  Future<void> save(CloudSource source) => _mutationLock.synchronized(() async {
        final sources = await getAll();
        final index = sources.indexWhere((current) => current.id == source.id);
        if (index < 0) {
          sources.add(source);
        } else {
          sources[index] = source;
        }
        await _storage.write(
          sources.map((item) => item.toJson()).toList(growable: false),
        );
      });

  Future<void> updateScanSummary(
    String sourceId, {
    required CloudScanStatus status,
    DateTime? scannedAt,
    int? videoCount,
    int? subtitleCount,
    int? failureCount,
  }) =>
      _mutationLock.synchronized(() async {
        final sources = await getAll();
        final index = sources.indexWhere((source) => source.id == sourceId);
        if (index < 0) return;
        final source = sources[index];
        sources[index] = source.copyWith(
          scanStatus: status,
          lastScannedAt: scannedAt,
          indexedVideoCount: videoCount,
          matchedSubtitleCount: subtitleCount,
          lastScanFailureCount: failureCount,
        );
        await _storage.write(
          sources.map((item) => item.toJson()).toList(growable: false),
        );
      });

  Future<bool> delete(String sourceId) => _mutationLock.synchronized(() async {
        final sources = await getAll();
        final remaining =
            sources.where((source) => source.id != sourceId).toList();
        if (remaining.length == sources.length) return false;
        final previousCredential = await _credentialStore.read(sourceId);
        await _credentialStore.delete(sourceId);
        try {
          await _storage.write(
            remaining.map((source) => source.toJson()).toList(growable: false),
          );
        } on Object {
          if (previousCredential != null) {
            await _credentialStore.write(sourceId, previousCredential);
          }
          rethrow;
        }
        return true;
      });

  Future<String> exportJson() async => jsonEncode(
        (await getAll())
            .map((source) => source.toJson())
            .toList(growable: false),
      );
}
