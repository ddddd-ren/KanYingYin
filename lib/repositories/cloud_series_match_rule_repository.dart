import 'dart:convert';

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

  Future<List<CloudSeriesMatchRule>> getAll() => _getAll();

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

  /// 只提交仍匹配原快照的目标；回滚跳过冲突并返回未恢复的键。
  Future<Set<String>> patchRecords(
    Map<String, CloudSeriesMatchRule?> updates, {
    required Map<String, CloudSeriesMatchRule?> originals,
    bool skipConflicts = false,
  }) {
    if (updates.length != originals.length ||
        updates.keys.any((key) => !originals.containsKey(key)) ||
        [...updates.entries, ...originals.entries].any((entry) =>
            entry.value != null && entry.value!.stableKey != entry.key)) {
      throw ArgumentError('条件更新必须提供同一组身份及完整原值');
    }
    return _lock.synchronized(() async {
      if (updates.isEmpty) return <String>{};
      final payload = await _storage.read();
      final records = payload.map(CloudSeriesMatchRule.fromJson).toList();
      final current = {for (final record in records) record.stableKey: record};
      if (current.length != records.length) {
        throw const FormatException('刮削记录身份重复，已停止覆盖');
      }
      final accepted = <String, CloudSeriesMatchRule?>{};
      final conflicts = <String>{};
      for (final entry in updates.entries) {
        final value = current[entry.key];
        final serialized = jsonEncode(value?.toJson());
        // 写前失败的回滚或重复提交可能已经处于目标状态。
        if (serialized == jsonEncode(entry.value?.toJson())) continue;
        if (serialized != jsonEncode(originals[entry.key]?.toJson())) {
          conflicts.add(entry.key);
        } else {
          accepted[entry.key] = entry.value;
        }
      }
      if (conflicts.isNotEmpty && !skipConflicts) {
        throw StateError('刮削记录已变化，请重新确认导入');
      }
      if (accepted.isNotEmpty) {
        await _storage.write([
          for (var index = 0; index < records.length; index++)
            if (!accepted.containsKey(records[index].stableKey))
              payload[index]
            else if (accepted[records[index].stableKey] case final replacement?)
              replacement.toJson(),
          for (final entry in accepted.entries)
            if (!current.containsKey(entry.key) && entry.value != null)
              entry.value!.toJson(),
        ]);
      }
      return conflicts;
    });
  }

  Future<void> replaceAll(Iterable<CloudSeriesMatchRule> replacements) {
    return _lock.synchronized(
      () => _write(replacements.toList(growable: false)),
    );
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
