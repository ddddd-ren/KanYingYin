import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TMDB 图片界面不再使用绕过代理的 Image.network', () {
    const files = <String>[
      'lib/pages/tmdb_match_dialog.dart',
      'lib/pages/local/tmdb_match_sheet.dart',
      'lib/pages/local/library_sheet.dart',
      'lib/pages/local/local_series_detail_page.dart',
      'lib/pages/cloud/resources/cloud_resource_poster_wall.dart',
      'lib/pages/cloud/resources/cloud_resource_episode_sheet.dart',
      'lib/features/library/presentation/media_category_page.dart',
      'lib/features/library/presentation/library_media_grid.dart',
      'lib/features/history/presentation/history_page.dart',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('Image.network(')),
        reason: '$path 必须通过统一 TMDB 图片客户端加载远程海报',
      );
    }
  });
}
