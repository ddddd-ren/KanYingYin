import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('所有选集和版本入口复用技术标签解析器与标签行', () {
    const paths = <String>[
      'lib/pages/cloud/resources/cloud_resource_episode_sheet.dart',
      'lib/pages/local/local_series_detail_page.dart',
      'lib/pages/local/library_sheet.dart',
      'lib/features/library/presentation/media_category_page.dart',
      'lib/features/library/presentation/media_library_details_dialog.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, contains('MediaTechnicalBadgeResolver'), reason: path);
      expect(source, contains('MediaTechnicalBadgeRow'), reason: path);
    }
  });
}
