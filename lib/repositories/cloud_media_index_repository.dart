import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class CloudMediaIndexStorage {
  Object get synchronizationIdentity;
  Future<Map<String, Object?>> read();
  Future<void> write(Map<String, Object?> value);
}

class HiveCloudMediaIndexStorage implements CloudMediaIndexStorage {
  static final Object _identity = Object();

  @override
  Object get synchronizationIdentity => _identity;

  @override
  Future<Map<String, Object?>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.cloudMediaIndex,
      defaultValue: const <String, Object?>{},
    );
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }

  @override
  Future<void> write(Map<String, Object?> value) =>
      GStorage.setting.put(SettingBoxKey.cloudMediaIndex, value);
}

class MemoryCloudMediaIndexStorage implements CloudMediaIndexStorage {
  Map<String, Object?> _value = <String, Object?>{};

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<Map<String, Object?>> read() async =>
      Map<String, Object?>.from(_value);

  @override
  Future<void> write(Map<String, Object?> value) async {
    _value = Map<String, Object?>.from(value);
  }
}

class CloudMediaIndexSnapshot {
  const CloudMediaIndexSnapshot({
    required this.items,
    required this.fingerprints,
    required this.directoryEntries,
    required this.indexedRoots,
  });
  final List<CloudMediaIndexItem> items;
  final Map<String, String> fingerprints;
  final Map<String, List<CloudFileEntry>> directoryEntries;
  final List<String> indexedRoots;
}

class CloudMediaIndexRepository {
  static final Expando<Lock> _locks = Expando<Lock>();

  CloudMediaIndexRepository({CloudMediaIndexStorage? storage})
      : _storage = storage ?? HiveCloudMediaIndexStorage() {
    final identity = _storage.synchronizationIdentity;
    _lock = _locks[identity] ??= Lock();
  }

  final CloudMediaIndexStorage _storage;
  late final Lock _lock;
  Object get coordinationIdentity => _storage.synchronizationIdentity;

  Future<List<CloudMediaIndexItem>> getBySource(String sourceId) async =>
      (await snapshot(sourceId)).items;

  Future<CloudMediaIndexSnapshot> snapshot(String sourceId) async =>
      _snapshotFromData(sourceId, await _storage.read());

  static CloudMediaIndexSnapshot _snapshotFromData(
    String sourceId,
    Map<String, Object?> data,
  ) {
    final items = <CloudMediaIndexItem>[];
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final raw in rawItems.whereType<Map<Object?, Object?>>()) {
        try {
          final item = _itemFromJson(Map<String, Object?>.from(raw));
          if (item.sourceId == sourceId) items.add(item);
        } on Object {
          continue;
        }
      }
    }
    final fingerprints = <String, String>{};
    final rawFingerprints = data['fingerprints'];
    if (rawFingerprints is Map) {
      for (final entry in rawFingerprints.entries) {
        if (entry.key is String && entry.value is String) {
          final key = entry.key as String;
          if (key.startsWith('$sourceId|')) {
            fingerprints[key.substring(sourceId.length + 1)] =
                entry.value as String;
          }
        }
      }
    }
    final directoryEntries = <String, List<CloudFileEntry>>{};
    final rawDirectories = data['directoryEntries'];
    if (rawDirectories is Map) {
      for (final entry in rawDirectories.entries) {
        if (entry.key is! String ||
            !(entry.key as String).startsWith('$sourceId|') ||
            entry.value is! List) {
          continue;
        }
        final children = <CloudFileEntry>[];
        for (final raw in (entry.value as List<Object?>)
            .whereType<Map<Object?, Object?>>()) {
          try {
            children.add(_entryFromJson(Map<String, Object?>.from(raw)));
          } on Object {
            continue;
          }
        }
        directoryEntries[(entry.key as String).substring(sourceId.length + 1)] =
            children;
      }
    }
    final indexedRoots = <String>[];
    final rawIndexedRoots = data['indexedRoots'];
    if (rawIndexedRoots is Map && rawIndexedRoots[sourceId] is List) {
      indexedRoots.addAll(
        (rawIndexedRoots[sourceId] as List).whereType<String>(),
      );
    }
    return CloudMediaIndexSnapshot(
      items: items,
      fingerprints: fingerprints,
      directoryEntries: directoryEntries,
      indexedRoots: indexedRoots,
    );
  }

  Future<CloudMediaIndexSnapshot> removeSource(String sourceId) =>
      _lock.synchronized(() async {
        final data = await _storage.read();
        final removed = _snapshotFromData(sourceId, data);
        final retainedItems = <Object?>[];
        final rawItems = data['items'];
        if (rawItems is List) {
          for (final raw in rawItems) {
            if (raw is Map && raw['sourceId'] == sourceId) continue;
            retainedItems.add(raw);
          }
        }
        final retainedFingerprints = <String, Object?>{};
        final rawFingerprints = data['fingerprints'];
        if (rawFingerprints is Map) {
          for (final entry in rawFingerprints.entries) {
            if (entry.key is String &&
                !(entry.key as String).startsWith('$sourceId|')) {
              retainedFingerprints[entry.key as String] = entry.value;
            }
          }
        }
        final retainedDirectories = <String, Object?>{};
        final rawDirectories = data['directoryEntries'];
        if (rawDirectories is Map) {
          for (final entry in rawDirectories.entries) {
            if (entry.key is String &&
                !(entry.key as String).startsWith('$sourceId|')) {
              retainedDirectories[entry.key as String] = entry.value;
            }
          }
        }
        final retainedIndexedRoots = <String, Object?>{};
        final rawIndexedRoots = data['indexedRoots'];
        if (rawIndexedRoots is Map) {
          for (final entry in rawIndexedRoots.entries) {
            if (entry.key is String && entry.key != sourceId) {
              retainedIndexedRoots[entry.key as String] = entry.value;
            }
          }
        }
        await _storage.write(<String, Object?>{
          ...data,
          'items': retainedItems,
          'fingerprints': retainedFingerprints,
          'directoryEntries': retainedDirectories,
          'indexedRoots': retainedIndexedRoots,
        });
        return removed;
      });

  Future<void> replaceSource(
    String sourceId,
    List<CloudMediaIndexItem> items,
    Map<String, String> fingerprints,
    Map<String, List<CloudFileEntry>> directoryEntries,
    List<String> indexedRoots,
  ) =>
      _lock.synchronized(() async {
        final data = await _storage.read();
        final retainedItems = <Object?>[];
        final rawItems = data['items'];
        if (rawItems is List) {
          for (final raw in rawItems.whereType<Map<Object?, Object?>>()) {
            if (raw['sourceId'] != sourceId) retainedItems.add(raw);
          }
        }
        retainedItems.addAll(items.map(_itemToJson));
        final retainedFingerprints = <String, Object?>{};
        final rawFingerprints = data['fingerprints'];
        if (rawFingerprints is Map) {
          for (final entry in rawFingerprints.entries) {
            if (entry.key is String &&
                !('${entry.key}').startsWith('$sourceId|')) {
              retainedFingerprints[entry.key as String] = entry.value;
            }
          }
        }
        for (final entry in fingerprints.entries) {
          retainedFingerprints['$sourceId|${entry.key}'] = entry.value;
        }
        final retainedDirectories = <String, Object?>{};
        final rawDirectories = data['directoryEntries'];
        if (rawDirectories is Map) {
          for (final entry in rawDirectories.entries) {
            if (entry.key is String &&
                !('${entry.key}').startsWith('$sourceId|')) {
              retainedDirectories[entry.key as String] = entry.value;
            }
          }
        }
        for (final entry in directoryEntries.entries) {
          retainedDirectories['$sourceId|${entry.key}'] =
              entry.value.map(_entryToJson).toList(growable: false);
        }
        final retainedIndexedRoots = <String, Object?>{};
        final rawIndexedRoots = data['indexedRoots'];
        if (rawIndexedRoots is Map) {
          for (final entry in rawIndexedRoots.entries) {
            if (entry.key is String && entry.key != sourceId) {
              retainedIndexedRoots[entry.key as String] = entry.value;
            }
          }
        }
        retainedIndexedRoots[sourceId] = indexedRoots;
        await _storage.write(<String, Object?>{
          'items': retainedItems,
          'fingerprints': retainedFingerprints,
          'directoryEntries': retainedDirectories,
          'indexedRoots': retainedIndexedRoots,
        });
      });

  Future<int> updateMatching(
    String sourceId,
    bool Function(CloudMediaIndexItem item) matches,
    CloudMediaIndexItem Function(CloudMediaIndexItem item) update,
  ) =>
      _lock.synchronized(() async {
        final data = await _storage.read();
        final rawItems = data['items'];
        if (rawItems is! List) return 0;
        var count = 0;
        final items = <Object?>[];
        for (final raw in rawItems) {
          if (raw is! Map) {
            items.add(raw);
            continue;
          }
          try {
            final item = _itemFromJson(Map<String, Object?>.from(raw));
            if (item.sourceId == sourceId && matches(item)) {
              items.add(_itemToJson(update(item)));
              count++;
            } else {
              items.add(raw);
            }
          } on Object {
            items.add(raw);
          }
        }
        if (count > 0) {
          await _storage.write(<String, Object?>{...data, 'items': items});
        }
        return count;
      });

  static CloudMediaIndexItem _itemFromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) throw const FormatException();
      return value;
    }

    final size = json['size'];
    if (size is! int) throw const FormatException();
    return CloudMediaIndexItem(
      sourceId: requiredString('sourceId'),
      remoteId: requiredString('remoteId'),
      remotePath: requiredString('remotePath'),
      name: requiredString('name'),
      size: size,
      modifiedAt: DateTime.tryParse(
          json['modifiedAt'] is String ? json['modifiedAt'] as String : ''),
      seriesName: requiredString('seriesName'),
      seasonNumber:
          json['seasonNumber'] is int ? json['seasonNumber'] as int : null,
      episodeNumber:
          json['episodeNumber'] is int ? json['episodeNumber'] as int : null,
      mediaType: CloudMediaType.values.firstWhere(
        (value) => value.name == json['mediaType'],
        orElse: () => CloudMediaType.unknown,
      ),
      subtitlePaths: json['subtitlePaths'] is List
          ? (json['subtitlePaths'] as List).whereType<String>().toList()
          : const <String>[],
      tmdbId: json['tmdbId'] is int ? json['tmdbId'] as int : null,
      tmdbTitle: json['tmdbTitle'] as String?,
      tmdbOriginalTitle: json['tmdbOriginalTitle'] as String?,
      tmdbOverview: json['tmdbOverview'] as String?,
      tmdbRating: json['tmdbRating'] is num
          ? (json['tmdbRating'] as num).toDouble()
          : null,
      tmdbPosterUrl: json['tmdbPosterUrl'] as String?,
      tmdbBackdropUrl: json['tmdbBackdropUrl'] as String?,
      posterCachePath: json['posterCachePath'] as String?,
    );
  }

  static Map<String, Object?> _itemToJson(CloudMediaIndexItem item) =>
      <String, Object?>{
        'sourceId': item.sourceId,
        'remoteId': item.remoteId,
        'remotePath': item.remotePath,
        'name': item.name,
        'size': item.size,
        'modifiedAt': item.modifiedAt?.toIso8601String(),
        'seriesName': item.seriesName,
        'seasonNumber': item.seasonNumber,
        'episodeNumber': item.episodeNumber,
        'mediaType': item.mediaType.name,
        'subtitlePaths': item.subtitlePaths,
        'tmdbId': item.tmdbId,
        'tmdbTitle': item.tmdbTitle,
        'tmdbOriginalTitle': item.tmdbOriginalTitle,
        'tmdbOverview': item.tmdbOverview,
        'tmdbRating': item.tmdbRating,
        'tmdbPosterUrl': item.tmdbPosterUrl,
        'tmdbBackdropUrl': item.tmdbBackdropUrl,
        'posterCachePath': item.posterCachePath,
      };

  static CloudFileEntry _entryFromJson(Map<String, Object?> json) {
    final id = json['id'];
    final remotePath = json['remotePath'];
    final name = json['name'];
    final size = json['size'];
    final isDirectory = json['isDirectory'];
    if (id is! String ||
        remotePath is! String ||
        name is! String ||
        size is! int ||
        isDirectory is! bool) {
      throw const FormatException();
    }
    return CloudFileEntry(
      id: id,
      remotePath: remotePath,
      name: name,
      size: size,
      modifiedAt: DateTime.tryParse(
        json['modifiedAt'] is String ? json['modifiedAt'] as String : '',
      ),
      isDirectory: isDirectory,
    );
  }

  static Map<String, Object?> _entryToJson(CloudFileEntry entry) =>
      <String, Object?>{
        'id': entry.id,
        'remotePath': entry.remotePath,
        'name': entry.name,
        'size': entry.size,
        'modifiedAt': entry.modifiedAt?.toIso8601String(),
        'isDirectory': entry.isDirectory,
      };
}
