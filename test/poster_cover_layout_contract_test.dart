import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<String> _source(String path) => File(path).readAsString();

void main() {
  test('所有通用海报墙使用精确 2 比 3 比例', () async {
    final library = await _source(
      'lib/features/library/presentation/library_media_grid.dart',
    );
    final cloud = await _source(
      'lib/pages/cloud/resources/cloud_resource_poster_wall.dart',
    );
    final category = await _source(
      'lib/features/library/presentation/media_category_page.dart',
    );

    expect(
      RegExp('fallbackChildAspectRatio: posterAspectRatio').allMatches(library),
      hasLength(2),
    );
    expect(cloud, contains('childAspectRatio: posterAspectRatio'));
    expect(cloud, contains('fallbackChildAspectRatio: posterAspectRatio'));
    expect(
      RegExp('posterAspectRatio').allMatches(category).length,
      greaterThanOrEqualTo(2),
    );
    expect('$library$cloud$category', isNot(contains('0.68')));
  });

  test('紧凑封面入口使用统一 2 比 3 尺寸', () async {
    final history = await _source(
      'lib/features/history/presentation/history_page.dart',
    );
    final tmdb = await _source('lib/pages/tmdb_match_dialog.dart');
    final local = await _source('lib/pages/local/library_sheet.dart');
    final season = await _source(
      'lib/pages/cloud/resources/cloud_resource_episode_sheet.dart',
    );

    expect(history, contains('width: 60,'));
    expect(history, contains('height: 90,'));
    expect(tmdb, contains('width: 56,'));
    expect(tmdb, contains('height: 84,'));
    expect(local, contains('width: 40,'));
    expect(
      RegExp('height: 60,').allMatches(local).length,
      greaterThanOrEqualTo(3),
    );
    expect(season, contains('width: 92,'));
    expect(season, contains('height: 138,'));
  });

  test('封面失败状态不再使用彩色圆形或损坏图片图标', () async {
    final sources = await Future.wait([
      _source('lib/features/library/presentation/library_media_grid.dart'),
      _source('lib/features/library/presentation/media_category_page.dart'),
      _source('lib/features/history/presentation/history_page.dart'),
      _source('lib/pages/tmdb_match_dialog.dart'),
      _source('lib/pages/local/library_sheet.dart'),
    ]);
    final joined = sources.join();

    expect(joined, isNot(contains('Icons.broken_image_outlined')));
    expect(joined, isNot(contains('Icons.movie_creation_outlined')));
    expect(joined, contains('PosterCover.placeholder'));
  });
}
