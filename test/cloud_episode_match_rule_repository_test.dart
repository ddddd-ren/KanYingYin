import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_episode_match_rule.dart';
import 'package:kanyingyin/repositories/cloud_episode_match_rule_repository.dart';

void main() {
  test('映射和保留原名规则支持 JSON 往返', () {
    final mapped = CloudEpisodeMatchRule.mapped(
      sourceId: 'quark-1',
      remoteId: 'video-1',
      remotePath: r'\Show\S01E01.mkv',
      tmdbId: 196285,
      seasonNumber: 1,
      episodeNumber: 1,
      updatedAt: DateTime.utc(2026, 8, 6),
    );
    final keepOriginal = CloudEpisodeMatchRule.keepOriginal(
      sourceId: 'quark-1',
      remoteId: 'video-2',
      remotePath: '/Show/S01E02.mkv',
      tmdbId: 196285,
      updatedAt: DateTime.utc(2026, 8, 6),
    );

    expect(CloudEpisodeMatchRule.fromJson(mapped.toJson()), mapped);
    expect(CloudEpisodeMatchRule.fromJson(keepOriginal.toJson()), keepOriginal);
    expect(mapped.remotePath, '/Show/S01E01.mkv');
    expect(keepOriginal.mode, CloudEpisodeMatchMode.keepOriginal);
    expect(keepOriginal.seasonNumber, isNull);
  });

  test('远程 ID 或路径变化后规则不命中', () {
    final rule = _mapped('quark-1', 'video-1', '/Show/S01E01.mkv', 1);

    expect(
      rule.matches(
        sourceId: 'quark-1',
        remoteId: 'video-1',
        remotePath: '/Show/S01E01.mkv',
      ),
      isTrue,
    );
    expect(
      rule.matches(
        sourceId: 'quark-1',
        remoteId: 'video-2',
        remotePath: '/Show/S01E01.mkv',
      ),
      isFalse,
    );
    expect(
      rule.matches(
        sourceId: 'quark-1',
        remoteId: 'video-1',
        remotePath: '/Moved/S01E01.mkv',
      ),
      isFalse,
    );
  });

  test('批量替换只影响目标视频并保留其他来源规则', () async {
    final storage = MemoryCloudEpisodeMatchRuleStorage();
    final repository = CloudEpisodeMatchRuleRepository(storage: storage);
    final first = _mapped('quark-1', 'video-1', '/Show/S01E01.mkv', 1);
    final second = _mapped('quark-1', 'video-2', '/Show/S01E02.mkv', 2);
    final retained = _mapped('baidu-1', 'video-3', '/Show/S01E03.mkv', 3);
    await Future.wait(<Future<void>>[
      repository.upsert(first),
      repository.upsert(second),
      repository.upsert(retained),
    ]);
    final replacement = CloudEpisodeMatchRule.keepOriginal(
      sourceId: first.sourceId,
      remoteId: first.remoteId,
      remotePath: first.remotePath,
      tmdbId: first.tmdbId,
      updatedAt: DateTime.utc(2026, 8, 7),
    );

    await repository.replaceItems(
      targetKeys: <String>{first.stableKey},
      replacements: <CloudEpisodeMatchRule>[replacement],
    );

    expect(await repository.get(first.stableKey), replacement);
    expect(await repository.get(second.stableKey), second);
    expect(await repository.get(retained.stableKey), retained);

    await repository.replaceItems(
      targetKeys: <String>{replacement.stableKey},
      replacements: const <CloudEpisodeMatchRule>[],
    );
    expect(await repository.get(replacement.stableKey), isNull);
  });

  test('损坏规则不会阻止读取其他有效规则', () async {
    final storage = MemoryCloudEpisodeMatchRuleStorage();
    final valid = _mapped('quark-1', 'video-1', '/Show/S01E01.mkv', 1);
    await storage.write(<Map<String, Object?>>[
      <String, Object?>{'sourceId': 42},
      valid.toJson(),
    ]);
    final repository = CloudEpisodeMatchRuleRepository(storage: storage);

    expect(await repository.getBySource('quark-1'), <CloudEpisodeMatchRule>[
      valid,
    ]);
  });
}

CloudEpisodeMatchRule _mapped(
  String sourceId,
  String remoteId,
  String remotePath,
  int episodeNumber,
) {
  return CloudEpisodeMatchRule.mapped(
    sourceId: sourceId,
    remoteId: remoteId,
    remotePath: remotePath,
    tmdbId: 196285,
    seasonNumber: 1,
    episodeNumber: episodeNumber,
    updatedAt: DateTime.utc(2026, 8, 6),
  );
}
