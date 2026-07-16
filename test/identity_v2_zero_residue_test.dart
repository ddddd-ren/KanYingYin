import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('运行时代码和产品资源不包含旧项目名称', () {
    final result = Process.runSync(
      'git',
      ['ls-files', '-z'],
      stdoutEncoding: null,
    );
    expect(result.exitCode, 0);
    final paths = String.fromCharCodes(result.stdout as Uint8List)
        .split('\x00')
        .where((path) => path.isNotEmpty);
    const forbidden = <int>[107, 97, 122, 117, 109, 105];
    final matches = <String>[];

    for (final path in paths) {
      if (_allowsAttribution(path)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      final lower = bytes
          .map((byte) => byte >= 65 && byte <= 90 ? byte + 32 : byte)
          .toList(growable: false);
      if (_containsBytes(lower, forbidden)) matches.add(path);
    }

    expect(matches, isEmpty, reason: matches.join('\n'));
  });

  test('版本和 MSIX 身份使用 2.0 断代配置', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 2.0.7+20007'));
    expect(pubspec, contains('identity_name: com.kanyingyin.player.v2'));
    expect(pubspec, contains('publisher: CN=KanYingYin'));
    expect(pubspec, contains('msix_version: 2.0.7.0'));
    expect(pubspec, contains('install_certificate: false'));
  });
}

bool _allowsAttribution(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized == 'README.md' ||
      normalized == 'LICENSE' ||
      normalized == 'NOTICE' ||
      normalized == 'THIRD_PARTY_NOTICES.md' ||
      normalized.startsWith('docs/');
}

bool _containsBytes(List<int> source, List<int> pattern) {
  if (pattern.isEmpty || source.length < pattern.length) return false;
  for (var offset = 0; offset <= source.length - pattern.length; offset++) {
    var matches = true;
    for (var index = 0; index < pattern.length; index++) {
      if (source[offset + index] != pattern[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
