import 'dart:io';

import 'package:path/path.dart' as p;

class LegacyHistoryDataCleaner {
  const LegacyHistoryDataCleaner._();

  static Future<void> deleteFrom(Directory directory) async {
    for (final name in const ['histories.hive', 'histories.lock']) {
      final file = File(p.join(directory.path, name));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
