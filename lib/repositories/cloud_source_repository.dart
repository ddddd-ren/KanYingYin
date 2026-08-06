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

class CloudSourcePairingEntry {
  const CloudSourcePairingEntry({
    required this.source,
    this.credential,
  });

  final CloudSource source;
  final CloudCredential? credential;

  @override
  String toString() =>
      'CloudSourcePairingEntry(sourceId: ${source.id}, hasCredential: ${credential != null})';
}

class CloudSourcePairingRollbackException implements Exception {
  const CloudSourcePairingRollbackException(this.sourceIds);

  final List<String> sourceIds;

  @override
  String toString() =>
      'CloudSourcePairingRollbackException(sourceIds: ${sourceIds.join(',')})';
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
        .whereType<Map<Object?, Object?>>()
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

  Future<CloudSource?> updateSource(
    String sourceId,
    CloudSource Function(CloudSource current) update,
  ) =>
      _mutationLock.synchronized(() async {
        final sources = await getAll();
        final index = sources.indexWhere((source) => source.id == sourceId);
        if (index < 0) return null;
        final current = sources[index];
        final updated = update(current);
        if (updated.id != sourceId) {
          throw StateError('更新网盘数据源时不能修改来源 ID');
        }
        if (updated == current) return current;
        sources[index] = updated;
        await _storage.write(
          sources.map((source) => source.toJson()).toList(growable: false),
        );
        return updated;
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

  Future<List<CloudSourcePairingEntry>> exportForPairing() =>
      _mutationLock.synchronized(() async {
        final entries = <CloudSourcePairingEntry>[];
        for (final source in await getAll()) {
          entries.add(CloudSourcePairingEntry(
            source: source,
            credential: await _credentialStore.read(source.id),
          ));
        }
        return List<CloudSourcePairingEntry>.unmodifiable(entries);
      });

  Future<void> importForPairing(List<CloudSourcePairingEntry> entries) =>
      _mutationLock.synchronized(() async {
        if (entries.isEmpty) return;
        final sourceIds = <String>{};
        for (final entry in entries) {
          final sourceId = entry.source.id.trim();
          if (sourceId.isEmpty) {
            throw ArgumentError.value(sourceId, 'sourceId', '来源 ID 不能为空');
          }
          if (!sourceIds.add(sourceId)) {
            throw ArgumentError.value(sourceId, 'sourceId', '来源 ID 不能重复');
          }
        }

        final previousSources = await getAll();
        final previousCredentials = <String, CloudCredential?>{};
        for (final sourceId in sourceIds) {
          previousCredentials[sourceId] = await _credentialStore.read(sourceId);
        }

        final mergedSources = List<CloudSource>.of(previousSources);
        for (final entry in entries) {
          final index = mergedSources.indexWhere(
            (source) => source.id == entry.source.id,
          );
          if (index < 0) {
            mergedSources.add(entry.source);
          } else {
            mergedSources[index] = entry.source;
          }
        }

        try {
          for (final entry in entries) {
            final credential = entry.credential;
            if (credential == null || credential.isEmpty) {
              await _credentialStore.delete(entry.source.id);
            } else {
              await _credentialStore.write(entry.source.id, credential);
            }
          }
          await _storage.write(
            mergedSources
                .map((source) => source.toJson())
                .toList(growable: false),
          );
        } on Object {
          await _restorePairingSnapshot(
            previousSources: previousSources,
            previousCredentials: previousCredentials,
          );
          rethrow;
        }
      });

  Future<void> _restorePairingSnapshot({
    required List<CloudSource> previousSources,
    required Map<String, CloudCredential?> previousCredentials,
  }) async {
    var rollbackFailed = false;
    try {
      await _storage.write(
        previousSources
            .map((source) => source.toJson())
            .toList(growable: false),
      );
    } on Object {
      rollbackFailed = true;
    }
    for (final entry in previousCredentials.entries) {
      try {
        final credential = entry.value;
        if (credential == null) {
          await _credentialStore.delete(entry.key);
        } else {
          await _credentialStore.write(entry.key, credential);
        }
      } on Object {
        rollbackFailed = true;
      }
    }
    if (rollbackFailed) {
      throw CloudSourcePairingRollbackException(
        List<String>.unmodifiable(previousCredentials.keys),
      );
    }
  }
}
