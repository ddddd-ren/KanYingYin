import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('本地网盘和分类海报把汇总标签传给统一卡片', () {
    final expectations = <String, String>{
      'lib/features/library/presentation/library_media_grid.dart':
          'technicalBadges: item.technicalBadges',
      'lib/pages/cloud/resources/cloud_resource_poster_wall.dart':
          'technicalBadges: data.technicalBadges',
      'lib/features/library/presentation/media_category_page.dart':
          'technicalBadges: info.technicalBadges',
    };
    for (final entry in expectations.entries) {
      expect(
        File(entry.key).readAsStringSync(),
        contains(entry.value),
        reason: entry.key,
      );
    }
  });
}
