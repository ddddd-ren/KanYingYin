import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('观看历史仅网盘分支使用统一海报组件', () async {
    final source = await File(
      'lib/features/history/presentation/history_page.dart',
    ).readAsString();
    final posterSource = source.substring(source.indexOf('class _Poster'));

    expect(posterSource, contains('if (entry.isCloud)'));
    expect(posterSource, contains('return CloudPosterImage('));
    expect(
      posterSource.indexOf('if (entry.isCloud)'),
      lessThan(posterSource.indexOf('final cached = entry.posterCachePath')),
    );
    expect(
      RegExp(r'return CloudPosterImage\(').allMatches(posterSource),
      hasLength(1),
    );

    expect(source, contains('findItemIndexCallback: (key)'));
    expect(source, contains("const prefix = 'history-entry-'"));
  });
}
