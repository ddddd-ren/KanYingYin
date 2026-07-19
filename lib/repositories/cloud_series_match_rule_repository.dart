import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class CloudSeriesMatchRuleStorage {
  Object get synchronizationIdentity;

  Future<List<Map<String, Object?>>> read();

  Future<void> write(List<Map<String, Object?>> rules);
}

class HiveCloudSeriesMatchRuleStorage implements CloudSeriesMatchRuleStorage {
  static final Object _identity = Object();

  @override
  Object get synchronizationIdentity => _identity;

  @override
  Future<List<Map<String, Object?>>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.cloudSeriesMatchRules,
      defaultValue: const <Map<String, Object?>>[],
    );
    if (value is! List) return <Map<String, Object?>>[];
    return value
        .whereType<Map<Object?, Object?>>()
        .map((rule) => Map<String, Object?>.from(rule))
        .toList(growable: false);
  }

  @override
  Future<void> write(List<Map<String, Object?>> rules) {
    return GStorage.setting.put(SettingBoxKey.cloudSeriesMatchRules, rules);
  }
}

class MemoryCloudSeriesMatchRuleStorage implements CloudSeriesMatchRuleStorage {
  List<Map<String, Object?>> _rules = <Map<String, Object?>>[];

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, Object?>>> read() async => _rules
      .map((rule) => Map<String, Object?>.from(rule))
      .toList(growable: false);

  @override
  Future<void> write(List<Map<String, Object?>> rules) async {
    _rules = rules
        .map((rule) => Map<String, Object?>.from(rule))
        .toList(growable: false);
  }
}

class CloudSeriesMatchRuleRepository {
  static final Expando<Lock> _locks = Expando<Lock>();

  CloudSeriesMatchRuleRepository({CloudSeriesMatchRuleStorage? storage})
      : _storage = storage ?? HiveCloudSeriesMatchRuleStorage() {
    final identity = _storage.synchronizationIdentity;
    _lock = _locks[identity] ??= Lock();
  }

  final CloudSeriesMatchRuleStorage _storage;
  late final Lock _lock;

  Future<CloudSeriesMatchRule?> get(String stableKey) async {
    for (final rule in await _getAll()) {
      if (rule.stableKey == stableKey) return rule;
    }
    return null;
  }

  Future<List<CloudSeriesMatchRule>> getBySource(String sourceId) async {
    return (await _getAll())
        .where((rule) => rule.sourceId == sourceId)
        .toList(growable: false);
  }

  Future<void> upsert(CloudSeriesMatchRule rule) {
    return _lock.synchronized(() async {
      final rules = await _getAll();
      final index = rules.indexWhere(
        (current) => current.stableKey == rule.stableKey,
      );
      if (index < 0) {
        rules.add(rule);
      } else {
        rules[index] = rule;
      }
      await _write(rules);
    });
  }

  Future<List<CloudSeriesMatchRule>> removeSource(String sourceId) {
    return _lock.synchronized(() async {
      final rules = await _getAll();
      final removed = rules
          .where((rule) => rule.sourceId == sourceId)
          .toList(growable: false);
      if (removed.isEmpty) return removed;
      await _write(
        rules.where((rule) => rule.sourceId != sourceId).toList(),
      );
      return removed;
    });
  }

  Future<void> replaceSource(
    String sourceId,
    List<CloudSeriesMatchRule> rules,
  ) {
    return _lock.synchronized(() async {
      final retained =
          (await _getAll()).where((rule) => rule.sourceId != sourceId).toList();
      retained.addAll(rules.where((rule) => rule.sourceId == sourceId));
      await _write(retained);
    });
  }

  Future<List<CloudSeriesMatchRule>> _getAll() async {
    final rules = <CloudSeriesMatchRule>[];
    for (final value in await _storage.read()) {
      try {
        rules.add(CloudSeriesMatchRule.fromJson(value));
      } on Object {
        // 单条损坏规则不能阻止其他系列继续自动继承。
      }
    }
    return rules;
  }

  Future<void> _write(List<CloudSeriesMatchRule> rules) {
    return _storage.write(
      rules.map((rule) => rule.toJson()).toList(growable: false),
    );
  }
}
