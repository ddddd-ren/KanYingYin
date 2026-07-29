import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 播放器组件供应脚本兼容 Windows PowerShell 5', () {
    final result = Process.runSync(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path 'tool/windows/prepare_compatible_libmpv.ps1'),
  [ref]$tokens,
  [ref]$errors
) | Out-Null
if ($errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Error $_.Message }
  exit 1
}
''',
      ],
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );

    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
  });

  test('Windows 构建只接受联合验证过的 D3D11、TrueHD 与 PGS 组件包', () {
    final config = File('windows/cmake/full_libmpv.cmake').readAsStringSync();
    final root = File('windows/CMakeLists.txt').readAsStringSync();
    final provisioner =
        File('tool/windows/prepare_compatible_libmpv.ps1').readAsStringSync();
    final player =
        File('lib/pages/player/player_controller.dart').readAsStringSync();

    expect(config, contains('KANYINGYIN_WINDOWS_LIBMPV_ROOT'));
    expect(
      config,
      contains('20260730-ad59ff1b4-ffmpeg8.1.2-r2'),
    );
    expect(config, contains('kanyingyin-libmpv-manifest.json'));
    expect(
      config,
      contains('string(JSON FULL_LIBMPV_MANIFEST_BUNDLE_ID GET'),
    );
    expect(
      config,
      contains('string(TOUPPER "\${FULL_LIBMPV_ACTUAL_SHA256}"'),
    );
    for (final dependency in <String>[
      'libmpv-2.dll',
      'avcodec-62.dll',
      'avformat-62.dll',
      'avutil-60.dll',
      'swresample-6.dll',
      'swscale-9.dll',
    ]) {
      expect(config, contains(dependency));
    }
    expect(config, contains('FULL_LIBMPV_RUNTIME_DLLS'));
    expect(config, contains('FULL_LIBMPV_FORBIDDEN_DLLS'));
    expect(config, contains('WebView2Loader.dll'));
    expect(config, isNot(contains('file(DOWNLOAD')));
    expect(config, isNot(contains('shinchiro')));
    expect(
      root,
      contains('list(FILTER PLUGIN_BUNDLED_LIBRARIES EXCLUDE REGEX'),
    );
    expect(root, contains('FULL_LIBMPV_RUNTIME_DLLS'));

    final pluginInstall = root.indexOf('if(PLUGIN_BUNDLED_LIBRARIES)');
    final fullMpvInstall =
        root.indexOf('install(FILES \${FULL_LIBMPV_RUNTIME_DLLS}');
    expect(fullMpvInstall, greaterThan(pluginInstall));
    expect(
      root,
      contains('install(FILES "\${FULL_LIBMPV_MANIFEST}"'),
    );
    expect(provisioner, contains('Selected decoder: truehd'));
    expect(provisioner, contains('Using subtitle decoder pgssub'));
    expect(provisioner, contains('Using hardware decoding (d3d11va)'));
    expect(provisioner, contains('mpv_render_context_render'));
    expect(provisioner, contains('Copy-Item'));
    expect(provisioner, contains(r'$excludedApplicationDllNames'));
    expect(provisioner, contains(r"-notmatch '_plugin\.dll$'"));
    expect(provisioner, contains('WebView2Loader.dll'));
    expect(provisioner, contains('.IndexOf('));
    expect(
      provisioner,
      isNot(contains('.Contains(\$Expected, [System.StringComparison]')),
    );
    expect(
        player, isNot(contains('hardwareDecoder = effectiveHardwareDecoder(')));
  });
}
