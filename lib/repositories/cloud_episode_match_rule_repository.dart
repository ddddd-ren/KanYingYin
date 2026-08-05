import 'package:kanyingyin/modules/cloud/cloud_episode_match_rule.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class CloudEpisodeMatchRuleStorage {
  Object get synchronizationIdentity;

  Future<List<Map<String, Object?>>> read();

  Future<void> write(List<Map<String, Object?>> rules);
}

final class HiveCloudEpisodeMatchRuleStorage
    implements CloudEpisodeMatchRuleStorage {
  static final Object _identity = Object();

  @override
  Object get synchronizationIdentity => _identity;

  @override
  Future<List<Map<String, Object?>>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.cloudEpisodeMatchRules,
      defaultValue: const <Map<String, Object?>>[],
    );
    if (value is! List) return const <Map<String, Object?>>[];
    return value
        .whereType<Map<Object?, Object?>>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  @override
  Future<void> write(List<Map<String, Object?>> rules) {
    return GStorage.setting.put(SettingBoxKey.cloudEpisodeMatchRules, rules);
  }
}

final class MemoryCloudEpisodeMatchRuleStorage
    implements CloudEpisodeMatchRuleStorage {
  List<Map<String, Object?>> _rules = <Map<String, Object?>>[];

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, Object?>>> read() async => _rules
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);

  @override
  Future<void> write(List<Map<String, Object?>> rules) async {
    _rules = rules
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }
}

final class CloudEpisodeMatchRuleRepository {
  CloudEpisodeMatchRuleRepository({CloudEpisodeMatchRuleStorage? storage})
      : _storage = storage ?? HiveCloudEpisodeMatchRuleStorage() {
    final identity = _storage.synchronizationIdentity;
    _lock = _locks[identity] ??= Lock();
  }

  static final Expando<Lock> _locks = Expando<Lock>();
  final CloudEpisodeMatchRuleStorage _storage;
  late final Lock _lock;

  Future<List<CloudEpisodeMatchRule>> getAll() => _getAll();

  Future<CloudEpisodeMatchRule?> get(String stableKey) async {
    for (final rule in await _getAll()) {
      if (rule.stableKey == stableKey) return rule;
    }
    return null;
  }

  Future<List<CloudEpisodeMatchRule>> getBySource(String sourceId) async {
    return (await _getAll())
        .where((rule) => rule.sourceId == sourceId)
        .toList(growable: false);
  }

  Future<void> upsert(CloudEpisodeMatchRule rule) {
    return replaceItems(
      targetKeys: <String>{rule.stableKey},
      replacements: <CloudEpisodeMatchRule>[rule],
    );
  }

  Future<void> remove(String stableKey) {
    return replaceItems(
      targetKeys: <String>{stableKey},
      replacements: const <CloudEpisodeMatchRule>[],
    );
  }

  Future<void> replaceItems({
    required Set<String> targetKeys,
    required Iterable<CloudEpisodeMatchRule> replacements,
  }) {
    return _lock.synchronized(() async {
      final next = (await _getAll())
          .where((rule) => !targetKeys.contains(rule.stableKey))
          .toList();
      for (final replacement in replacements) {
        next.removeWhere((rule) => rule.stableKey == replacement.stableKey);
        next.add(replacement);
      }
      await _write(next);
    });
  }

  Future<List<CloudEpisodeMatchRule>> _getAll() async {
    final result = <CloudEpisodeMatchRule>[];
    for (final json in await _storage.read()) {
      try {
        result.add(CloudEpisodeMatchRule.fromJson(json));
      } on Object {
        // 单条规则损坏时保留其他视频的手动匹配。
      }
    }
    return result;
  }

  Future<void> _write(List<CloudEpisodeMatchRule> rules) {
    return _storage.write(
      rules.map((rule) => rule.toJson()).toList(growable: false),
    );
  }
}
