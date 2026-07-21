import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('本地旧索引回退未知来源且新字段序列化往返', () {
    final legacy = LocalMediaIndexItem.fromJson(<String, dynamic>{
      'path': r'D:\Media\Movie.mkv',
      'name': 'Movie.mkv',
      'parentPath': r'D:\Media',
      'sourcePath': r'D:\Media',
      'size': 1,
      'modifiedMillis': 1,
      'seriesName': 'Movie',
      'indexedAtMillis': 1,
    });

    expect(legacy.tmdbMatchOrigin, TmdbMatchOrigin.legacyUnknown);
    expect(legacy.tmdbRuleVersion, 0);

    final restored = LocalMediaIndexItem.fromJson(
      legacy
          .copyWith(
            tmdbMatchOrigin: TmdbMatchOrigin.manual,
            tmdbRuleVersion: currentTmdbRuleVersion,
          )
          .toJson(),
    );
    expect(restored.tmdbMatchOrigin, TmdbMatchOrigin.manual);
    expect(restored.tmdbRuleVersion, currentTmdbRuleVersion);
  });

  test('网盘资源旧记录回退未知来源且新字段序列化往返', () {
    final legacy = CloudResourceTmdbRecord.fromJson(<String, Object?>{
      'sourceId': 'source',
      'remoteId': 'file',
      'remotePath': '/Movie.mkv',
      'displayName': 'Movie.mkv',
      'resourceKind': 'standaloneVideo',
      'status': 'matched',
      'checkedAtMillis': 1,
    });
    expect(legacy.tmdbMatchOrigin, TmdbMatchOrigin.legacyUnknown);
    expect(legacy.tmdbRuleVersion, 0);

    final restored = CloudResourceTmdbRecord.fromJson(<String, Object?>{
      ...legacy.toJson(),
      'tmdbMatchOrigin': TmdbMatchOrigin.automatic.name,
      'tmdbRuleVersion': currentTmdbRuleVersion,
    });
    expect(restored.tmdbMatchOrigin, TmdbMatchOrigin.automatic);
    expect(restored.tmdbRuleVersion, currentTmdbRuleVersion);
  });

  test('网盘作品旧记录回退未知来源且新字段序列化往返', () {
    final legacy = CloudWorkTmdbRecord.fromJson(<String, Object?>{
      'sourceId': 'source',
      'workKey': 'work',
      'workRootId': 'root',
      'workRootPath': '/Show',
      'remoteName': 'Show',
      'status': 'matched',
      'checkedAtMillis': 1,
    });
    expect(legacy.tmdbMatchOrigin, TmdbMatchOrigin.legacyUnknown);
    expect(legacy.tmdbRuleVersion, 0);

    final restored = CloudWorkTmdbRecord.fromJson(<String, Object?>{
      ...legacy.toJson(),
      'tmdbMatchOrigin': TmdbMatchOrigin.manual.name,
      'tmdbRuleVersion': currentTmdbRuleVersion,
    });
    expect(restored.tmdbMatchOrigin, TmdbMatchOrigin.manual);
    expect(restored.tmdbRuleVersion, currentTmdbRuleVersion);
  });
}
