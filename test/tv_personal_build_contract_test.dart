import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('个人 TV 构建只从环境读取密码并在 finally 清理私有资源', () {
    final script = File(
      'tool/android/build_personal_tv.ps1',
    ).readAsStringSync();

    expect(script, contains('[string]\$ConfigurationPath'));
    expect(script, contains('[string]\$MetadataPath'));
    expect(script, contains("'KYY_CONFIG_PASSWORD'"));
    expect(script, contains("'KYY_TV_PRELOAD_PASSWORD='"));
    expect(script, contains('-Flavor tvTest'));
    expect(script, contains('-ApkOnly'));
    expect(script, contains('-DartDefines'));
    expect(script, contains('finally'));
    expect(script, contains('configuration.kyyconfig'));
    expect(script, contains('metadata.kyymeta'));
    expect(script, contains(r'$personalEditionLabel ='));
    expect(script, contains('0x4E2A'));
    expect(script, contains('0x7248'));
    expect(script, isNot(contains('TV个人预置测试版')));
    expect(script, isNot(contains('personal-secret-must-not-be-embedded')));
  });

  test('输入路径校验失败后清空同一进程内的个人构建密码', () async {
    final script = File('tool/android/build_personal_tv.ps1').absolute;
    final residueParent = Directory(
      'build/app/intermediates/tv-preload-early-failure',
    ).absolute;
    final residue = Directory(
      '${residueParent.path}${Platform.pathSeparator}tv_preload',
    );
    await residue.create(recursive: true);
    await File(
      '${residue.path}${Platform.pathSeparator}configuration.kyyconfig',
    ).writeAsString('fixture');
    addTearDown(() async {
      if (await residueParent.exists()) {
        await residueParent.delete(recursive: true);
      }
    });
    final command = <String>[
      r"$ErrorActionPreference = 'Stop'",
      "[Environment]::SetEnvironmentVariable('KYY_CONFIG_PASSWORD', "
          "'fixture-config-password', 'Process')",
      "[Environment]::SetEnvironmentVariable('KYY_TV_PRELOAD_PASSWORD', "
          "'fixture-preload-password', 'Process')",
      "try { & '${_powerShellQuote(script.path)}' "
          "-ConfigurationPath 'missing.kyyconfig' "
          "-MetadataPath 'missing.kyymeta' } catch {}",
      r"$configPassword = [Environment]::GetEnvironmentVariable("
          "'KYY_CONFIG_PASSWORD', 'Process')",
      r"$preloadPassword = [Environment]::GetEnvironmentVariable("
          "'KYY_TV_PRELOAD_PASSWORD', 'Process')",
      r"if ($null -ne $configPassword -or $null -ne $preloadPassword) { "
          "throw 'process passwords were not cleared' }",
    ].join('; ');

    final result = await Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
    expect(await residue.exists(), isFalse);
  });

  test('安全清理 helper 删除 intermediates 下所有 tv_preload 目录', () async {
    final projectRoot = await Directory.systemTemp.createTemp(
      'tv-preload-cleanup-',
    );
    addTearDown(() => projectRoot.delete(recursive: true));
    final first = Directory(
      '${projectRoot.path}${Platform.pathSeparator}build'
      '${Platform.pathSeparator}app${Platform.pathSeparator}intermediates'
      '${Platform.pathSeparator}merged_assets${Platform.pathSeparator}tvTest'
      '${Platform.pathSeparator}tv_preload',
    );
    final second = Directory(
      '${projectRoot.path}${Platform.pathSeparator}build'
      '${Platform.pathSeparator}app${Platform.pathSeparator}intermediates'
      '${Platform.pathSeparator}flutter${Platform.pathSeparator}tvTest'
      '${Platform.pathSeparator}nested${Platform.pathSeparator}tv_preload',
    );
    for (final directory in <Directory>[first, second]) {
      await directory.create(recursive: true);
      for (final name in <String>[
        'configuration.kyyconfig',
        'metadata.kyymeta',
        'manifest.json',
        'resources.jar',
      ]) {
        await File(
          '${directory.path}${Platform.pathSeparator}$name',
        ).writeAsString('fixture');
      }
    }
    final helper = File(
      'tool/android/clear_personal_tv_build_residue.ps1',
    ).absolute;
    final helperPath = _powerShellQuote(helper.path);
    final projectRootPath = _powerShellQuote(projectRoot.path);
    final command = "\$ErrorActionPreference = 'Stop'; . '$helperPath'; "
        "Clear-PersonalTvBuildResidue -ProjectRoot '$projectRootPath'";

    final result = await Process.run(
      'powershell.exe',
      <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ],
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}',
    );
    final intermediates = Directory(
      '${projectRoot.path}${Platform.pathSeparator}build'
      '${Platform.pathSeparator}app${Platform.pathSeparator}intermediates',
    );
    final remaining = intermediates
        .listSync(recursive: true, followLinks: false)
        .whereType<Directory>()
        .where((directory) =>
            directory.uri.pathSegments.where((part) => part.isNotEmpty).last ==
            'tv_preload')
        .toList();
    expect(remaining, isEmpty);
  });

  test('通用 Android 构建支持可选 Dart Define 且普通 TV 脚本不要求个人文件', () {
    final release = File(
      'tool/android/build_signed_release.ps1',
    ).readAsStringSync();
    final normalTv = File(
      'tool/android/build_tv_test.ps1',
    ).readAsStringSync();

    expect(release, contains('[string[]]\$DartDefines'));
    expect(release, contains("'--dart-define'"));
    expect(normalTv, isNot(contains('KYY_CONFIG_PASSWORD')));
    expect(normalTv, isNot(contains('configuration.kyyconfig')));
    expect(normalTv, isNot(contains('metadata.kyymeta')));
  });

  test('构建校验工具只生成清单且不包含个人密码', () {
    final entrySource = File(
      'tool/tv_preload/validate_and_write_manifest.dart',
    ).readAsStringSync();
    final validatorSource = File(
      'tool/tv_preload/preload_validator.dart',
    ).readAsStringSync();
    final source = '$entrySource\n$validatorSource';

    expect(source, contains('Pbkdf2.hmacSha256'));
    expect(source, contains('AesGcm.with256bits'));
    expect(source, contains('ZipDecoder'));
    expect(source, contains('InputFileStream'));
    expect(source, contains('decodeStream'));
    expect(source, contains('KYY_CONFIG_PASSWORD'));
    expect(source, contains('sha256.bind'));
    expect(source, contains('configurationSha256'));
    expect(source, contains('metadataSha256'));
    expect(source, isNot(contains("import 'dart:ui'")));
    expect(source, isNot(contains("import 'package:flutter/")));
    expect(source, isNot(contains('ConfigurationArchiveCodec')));
    expect(source, isNot(contains('ScrapedMetadataArchiveCodec')));
    expect(source, isNot(contains('decodeBytes')));
    expect(source, isNot(contains('readAsBytes')));
    expect(source, isNot(contains('personal-secret-must-not-be-embedded')));
  });

  test('个人 TV 构建 finally 调用独立清理 helper 且各项清理隔离', () {
    final script = File(
      'tool/android/build_personal_tv.ps1',
    ).readAsStringSync();
    final helper = File(
      'tool/android/clear_personal_tv_build_residue.ps1',
    );

    expect(helper.existsSync(), isTrue);
    expect(script, contains('Clear-PersonalTvBuildResidue'));
    expect(script, contains('Invoke-PersonalTvCleanupStep'));
    expect(
      'Invoke-PersonalTvCleanupStep'.allMatches(script).length,
      greaterThanOrEqualTo(6),
    );
  });
}

String _powerShellQuote(String value) => value.replaceAll("'", "''");
