import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 构建覆盖为支持 TrueHD 与 PGS 的完整 libmpv', () {
    final config = File('windows/cmake/full_libmpv.cmake').readAsStringSync();
    final root = File('windows/CMakeLists.txt').readAsStringSync();
    final player =
        File('lib/pages/player/player_controller.dart').readAsStringSync();

    expect(config, contains('mpv-dev-x86_64-20260610-git-304426c.7z'));
    expect(
      config,
      contains(
        'SHA256=8cbb25ea784f01afbb3f904217cab1317430a8bcfd5680fd827a866367f71cc9',
      ),
    );
    expect(config, contains('EXPECTED_HASH'));
    expect(
      root,
      contains('list(FILTER PLUGIN_BUNDLED_LIBRARIES EXCLUDE REGEX'),
    );
    expect(root, contains('FULL_LIBMPV_DLL'));

    final pluginInstall = root.indexOf('if(PLUGIN_BUNDLED_LIBRARIES)');
    final fullMpvInstall = root.indexOf('install(FILES "\${FULL_LIBMPV_DLL}"');
    expect(fullMpvInstall, greaterThan(pluginInstall));
    expect(
        player, isNot(contains('hardwareDecoder = effectiveHardwareDecoder(')));
  });
}
