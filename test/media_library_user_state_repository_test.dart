import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';

void main() {
  for (final choice in <({
    String name,
    List<String>? categories,
    List<String>? genres,
  })>[
    (name: '人工选择', categories: ['动漫'], genres: ['动画']),
    (name: '人工清空', categories: [], genres: []),
    (name: '恢复自动', categories: null, genres: null),
    (name: '分类自动而题材清空', categories: null, genres: []),
    (name: '分类清空而题材自动', categories: [], genres: null),
  ]) {
    test('旧状态保存保留最新${choice.name}并更新普通标记与身份', () async {
      final storage = MemoryMediaLibraryUserStateStorage();
      final classificationRepository =
          MediaLibraryUserStateRepository(storage: storage);
      final ordinaryRepository = MediaLibraryUserStateRepository(storage: storage);
      await ordinaryRepository.save('work', const MediaLibraryUserState(
        favorite: true,
        collections: ['旧合集'],
        mediaIds: ['old-id'],
        categoryOverride: ['电影'],
        genreOverride: ['剧情'],
      ));
      final stale = (await ordinaryRepository.get('work'))!;
      final updatedAt = DateTime.utc(2026, 10, 11);
      final classificationSave = classificationRepository.saveClassification(
        'work',
        categories: choice.categories,
        genres: choice.genres,
        mediaIds: ['classified-id'],
      );
      final ordinarySave = ordinaryRepository.save(
        ' work ',
        stale.copyWith(
          favorite: false,
          watchLater: true,
          collections: ['稍后再看'],
          mediaIds: ['current-id'],
          updatedAt: updatedAt,
        ),
        preserveClassification: true,
      );
      await Future.wait([classificationSave, ordinarySave]);

      final saved = (await ordinaryRepository.get('work'))!;
      expect(saved.categoryOverride, choice.categories);
      expect(saved.genreOverride, choice.genres);
      expect(saved.favorite, isFalse);
      expect(saved.watchLater, isTrue);
      expect(saved.collections, ['稍后再看']);
      expect(saved.mediaIds, ['current-id']);
      expect(saved.updatedAt?.millisecondsSinceEpoch, updatedAt.millisecondsSinceEpoch);
    });
  }

  test('恢复自动已删除空记录时旧收藏保存不能重新引入分类', () async {
    final repository = MediaLibraryUserStateRepository(
      storage: MemoryMediaLibraryUserStateStorage(),
    );
    const stale = MediaLibraryUserState(
      categoryOverride: ['电影'],
      genreOverride: ['剧情'],
    );
    await repository.save('work', stale);
    await repository.saveClassification(
      'work', categories: null, genres: null, mediaIds: ['one'],
    );
    expect(await repository.get('work'), isNull);

    await repository.save('work', stale.copyWith(favorite: true),
        preserveClassification: true);

    final saved = (await repository.get('work'))!;
    expect(saved.favorite, isTrue);
    expect(saved.hasClassificationOverride, isFalse);
  });

  test('取消最后一个普通标记时保留最新人工清空记录', () async {
    final repository = MediaLibraryUserStateRepository(
      storage: MemoryMediaLibraryUserStateStorage(),
    );
    const stale = MediaLibraryUserState(favorite: true);
    await repository.save('work', stale);
    await repository.saveClassification(
      'work', categories: [], genres: [], mediaIds: ['one'],
    );

    await repository.save('work', stale.copyWith(favorite: false),
        preserveClassification: true);

    final saved = await repository.get('work');
    expect(saved, isNotNull);
    expect(saved!.favorite, isFalse);
    expect(saved.categoryOverride, isEmpty);
    expect(saved.genreOverride, isEmpty);
  });

  test('分类专用保存读取最新非分类状态并仅在写入成功后通知', () async {
    final storage = _FailingStorage({});
    final repository = MediaLibraryUserStateRepository(storage: storage);
    final initialChanges = MediaLibraryUserStateRepository.changes.value;
    await repository.save(
        'work',
        const MediaLibraryUserState(
          favorite: true,
          watchLater: true,
          collections: ['收藏合集'],
        ));
    expect(MediaLibraryUserStateRepository.changes.value, initialChanges + 1);
    await repository.saveClassification('work',
        categories: ['电影'], genres: <String>[], mediaIds: ['one']);
    final saved = (await repository.get('work'))!;
    expect(saved.favorite, isTrue);
    expect(saved.watchLater, isTrue);
    expect(saved.collections, ['收藏合集']);
    expect(saved.categoryOverride, ['电影']);
    expect(saved.genreOverride, <String>[]);
    expect(saved.mediaIds, ['one']);
    expect(saved.updatedAt, isNotNull);
    expect(MediaLibraryUserStateRepository.changes.value, initialChanges + 2);
    storage.failNextWrite = true;
    await expectLater(
        repository.saveClassification('work',
            categories: null, genres: null, mediaIds: ['one']),
        throwsStateError);
    expect(MediaLibraryUserStateRepository.changes.value, initialChanges + 2);
    expect((await repository.get('work'))!.categoryOverride, ['电影']);
    await repository.saveClassification('work',
        categories: null, genres: null, mediaIds: ['one']);
    final restored = (await repository.get('work'))!;
    expect(restored.favorite, isTrue);
    expect(restored.hasClassificationOverride, isFalse);
    expect(MediaLibraryUserStateRepository.changes.value, initialChanges + 3);
  });

  test('分类字段独立恢复自动，其他覆盖与普通用户状态保持不变', () {
    const state = MediaLibraryUserState(
      favorite: true,
      categoryOverride: ['电影'],
      genreOverride: <String>[],
    );
    final clearedCategory = state.copyWith(clearCategoryOverride: true);
    expect(clearedCategory.categoryOverride, isNull);
    expect(clearedCategory.genreOverride, <String>[]);
    expect(clearedCategory.hasClassificationOverride, isTrue);
    final clearedAll = clearedCategory.copyWith(clearGenreOverride: true);
    expect(clearedAll.hasClassificationOverride, isFalse);
    expect(clearedAll.favorite, isTrue);
  });

  test('没有其他标记时恢复自动删除覆盖记录，无效分类不会写入', () async {
    final storage = MemoryMediaLibraryUserStateStorage();
    final repository = MediaLibraryUserStateRepository(storage: storage);
    await repository.saveClassification('work',
        categories: <String>[], genres: null, mediaIds: ['one']);
    expect((await repository.get('work'))!.isEmpty, isFalse);
    await repository.saveClassification('work',
        categories: null, genres: null, mediaIds: ['one']);
    expect(await repository.get('work'), isNull);
    await expectLater(
        repository.saveClassification('work',
            categories: ['动漫', '电视剧'], genres: null, mediaIds: ['one']),
        throwsFormatException);
    expect(await storage.read(), isEmpty);
  });

  test('人工分类与手工清空重启后保留，自动状态仍不额外存储', () async {
    final storage = MemoryMediaLibraryUserStateStorage();
    final repository = MediaLibraryUserStateRepository(storage: storage);
    final raw = <String, Object?>{
      'categoryOverride': ['电影', '动漫'],
      'genreOverride': <String>[],
      'mediaIds': ['video:1'],
    };
    final state = MediaLibraryUserState.fromJson(raw);
    expect(state.toJson(), raw);
    expect(state.isEmpty, isFalse);
    await repository.save('work', state);
    final restarted = MediaLibraryUserStateRepository(storage: storage);
    expect((await restarted.get('work'))!.toJson(), raw);
    await restarted.save('work', MediaLibraryUserState.empty);
    expect(await restarted.get('work'), isNull);
  });

  test('未知分类、互斥分类及非列表覆盖在边界拒绝', () {
    for (final raw in <Map<Object?, Object?>>[
      {'categoryOverride': '电影'},
      {'categoryOverride': ['未知分类']},
      {'categoryOverride': ['动漫', '电视剧']},
      {'categoryOverride': [1]},
      {'genreOverride': '科幻'},
      {'genreOverride': [1]},
    ]) {
      expect(() => MediaLibraryUserState.fromJson(raw), throwsFormatException,
          reason: raw.toString());
    }
  });

  test('唯一媒体关联分别保留分类与题材，旧自动不覆盖新人工清空', () async {
    final repository = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage({
      'old': {
        'genreOverride': ['科幻'],
        'mediaIds': ['video:1']
      },
      'new': {'categoryOverride': <String>[]},
    }));
    final result = await repository.reconcile({
      'new': {'video:1'}
    });
    expect(result.keys, ['new']);
    expect(result['new']!.toJson()['categoryOverride'], <String>[]);
    expect(result['new']!.toJson()['genreOverride'], ['科幻']);
    await repository.remapMediaIds({'video:1': 'video:2'});
    expect((await repository.get('new'))!.toJson()['genreOverride'], ['科幻']);
  });

  for (final field in ['categoryOverride', 'genreOverride']) {
    test('$field 冲突不自动关联，显式关联失败且保留两份原状态', () async {
      final storage = MemoryMediaLibraryUserStateStorage({
        'old': {
          field: ['电影'],
          'mediaIds': ['video:1']
        },
        'new': {field: <String>[]},
      });
      final repository = MediaLibraryUserStateRepository(storage: storage);
      final result = await repository.reconcile({
        'new': {'video:1'}
      });
      expect(result.keys, containsAll(['old', 'new']));
      expect(result['old']!.toJson()[field], ['电影']);
      expect(result['new']!.toJson()[field], <String>[]);
      final before = await storage.read();
      await expectLater(repository.relink('old', 'new', {'video:1'}),
          throwsA(predicate<Object>((error) => error.toString().contains('冲突'))));
      expect(await storage.read(), before);
    });
  }

  test('分类保存失败保留磁盘原状态', () async {
    final storage = _FailingStorage({
      'work': {'categoryOverride': ['电影']}
    });
    final repository = MediaLibraryUserStateRepository(storage: storage);
    storage.failNextWrite = true;
    await expectLater(
        repository.save('work', MediaLibraryUserState.fromJson({
          'categoryOverride': <String>[],
        })),
        throwsStateError);
    expect((await repository.get('work'))!.toJson()['categoryOverride'], ['电影']);
  });

  test('部分媒体仍缺失时不把原作品状态转移到残缺分组', () async {
    final repository = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage({
      'old': {
        'favorite': true,
        'mediaIds': ['one', 'missing']
      }
    }));
    final all = await repository.reconcile({
      'new': {'one'}
    });
    expect(all.keys, ['old']);
    expect(all['old']!.mediaIds, ['one', 'missing']);
  });
  test('已确认改名只替换媒体成员，之后迁移到新作品', () async {
    final repository = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage({
      'old': {
        'favorite': true,
        'mediaIds': ['old.mp4']
      }
    }));
    await repository.remapMediaIds({'old.mp4': 'new.mp4'});
    final all = await repository.reconcile({
      'new': {'new.mp4'}
    });
    expect(all.keys, ['new']);
    expect(all['new']!.favorite, isTrue);
  });
  test('作品键变化时按媒体成员迁移并合并状态', () async {
    final storage = MemoryMediaLibraryUserStateStorage({
      'old': {
        'favorite': true,
        'collections': ['科幻'],
        'mediaIds': ['video:1']
      },
      'new': {
        'watchLater': true,
        'collections': ['科幻', '待补']
      },
    });
    final repository = MediaLibraryUserStateRepository(storage: storage);
    final result = await repository.reconcile({
      'new': {'video:1'}
    });
    expect(result.keys, ['new']);
    expect(result['new']!.favorite, isTrue);
    expect(result['new']!.watchLater, isTrue);
    expect(result['new']!.collections, ['科幻', '待补']);
    expect((await repository.get('new'))!.mediaIds, ['video:1']);
  });

  test('作品拆分或同名歧义时不自动转移旧状态', () async {
    final repository = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage({
      'old': {
        'favorite': true,
        'mediaIds': ['one', 'two']
      },
    }));
    final result = await repository.reconcile({
      'a': {'one'},
      'b': {'two'}
    });
    expect(result.keys, ['old']);
    await repository.relink('old', 'b', {'two'});
    expect(await repository.get('old'), isNull);
    expect((await repository.get('b'))!.favorite, isTrue);
  });

  test('用户状态按媒体库稳定键持久化并规范化合集', () async {
    final storage = MemoryMediaLibraryUserStateStorage();
    final repository = MediaLibraryUserStateRepository(storage: storage);

    await repository.save(
      ' local|作品 ',
      MediaLibraryUserState(
        favorite: true,
        watchLater: true,
        collections: <String>['  科幻  ', '科幻', '', 'x' * 33],
        updatedAt: DateTime.utc(2026, 10, 11),
      ),
    );

    expect(await repository.get('local|作品'), isNotNull);
    expect(
      (await repository.get('local|作品'))!.collections,
      const <String>['科幻'],
    );
    expect((await repository.getAll()).keys, contains('local|作品'));
  });

  test('空状态删除记录，损坏记录不会阻塞其他状态', () async {
    final storage = MemoryMediaLibraryUserStateStorage(<String, Object?>{
      'good': <String, Object?>{
        'favorite': true,
        'updatedAtMillis': 1,
        'collections': <String>['收藏'],
      },
      'broken': 'invalid',
    });
    final repository = MediaLibraryUserStateRepository(storage: storage);

    expect(await repository.get('good'), isNotNull);
    expect(await repository.get('broken'), isNull);

    await repository.save('good', MediaLibraryUserState.empty);
    expect(await repository.get('good'), isNull);
  });
}

class _FailingStorage extends MemoryMediaLibraryUserStateStorage {
  _FailingStorage(super.initialValue);

  bool failNextWrite = false;

  @override
  Future<void> write(Map<String, Object?> value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟状态写入失败');
    }
    await super.write(value);
  }
}
