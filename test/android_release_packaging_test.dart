import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Gradle 构建门禁校验 Windows 版本并使用独立 Android 版本', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final packageVersion = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(packageVersion, isNotNull);
    expect(
        gradle,
        contains(
            'val windowsVersionName = pubspecVersionMatch.groupValues[1]'));
    expect(
        gradle,
        contains(
            'val windowsVersionCode = pubspecVersionMatch.groupValues[2].toInt()'));
    expect(gradle, contains('val androidVersionName = "1.0.6"'));
    expect(gradle, contains('val androidVersionCode = 10006'));
  });

  test('Android mobile Release 使用当前版本契约并使用本机环境签名', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    for (final variable in const <String>[
      'KANYINGYIN_ANDROID_KEYSTORE',
      'KANYINGYIN_ANDROID_STORE_PASSWORD',
      'KANYINGYIN_ANDROID_KEY_ALIAS',
      'KANYINGYIN_ANDROID_KEY_PASSWORD',
    ]) {
      expect(gradle, contains('environmentVariable("$variable")'));
    }
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('isShrinkResources = true'));
    expect(gradle, contains('proguard-rules.pro'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(
        gradle,
        contains(
            'val windowsVersionName = pubspecVersionMatch.groupValues[1]'));
    expect(
        gradle,
        contains(
            'val windowsVersionCode = pubspecVersionMatch.groupValues[2].toInt()'));
    expect(gradle, contains('val androidVersionName = "1.0.6"'));
    expect(gradle, contains('val androidVersionCode = 10006'));
    expect(gradle, contains('create("mobile")'));
    expect(gradle, contains('create("tvTest")'));
    expect(gradle, contains('versionCode = androidVersionCode'));
    expect(gradle, contains('versionName = androidVersionName'));
  });

  test('Android Release 忽略未启用的 Play Core 延迟组件引用', () {
    final rules = File(
      'android/app/proguard-rules.pro',
    ).readAsStringSync();

    expect(rules, contains('-dontwarn com.google.android.play.core.**'));
  });

  test('Android 发布脚本构建、验证并复制 APK 和 AAB', () {
    final script = File(
      'tool/android/build_signed_release.ps1',
    ).readAsStringSync();

    expect(script, contains(r"$flutter = 'D:\flutter\bin\flutter.bat'"));
    expect(
      script,
      contains("'build', 'apk', '--release', '--flavor', \$Flavor, '--no-pub'"),
    );
    expect(script, contains(r'& $flutter @apkBuildArguments'));
    expect(
      script,
      contains(
        "'build', 'appbundle', '--release', '--flavor', \$Flavor, '--no-pub'",
      ),
    );
    expect(script, contains(r'& $flutter @aabBuildArguments'));
    expect(script, contains('apksigner.bat'));
    expect(script, contains('jarsigner.exe'));
    expect(script, contains('-verify -strict -keystore \$keystore'));
    expect(
      script,
      contains('-storepass:env KANYINGYIN_ANDROID_STORE_PASSWORD'),
    );
    expect(script, contains(r'$apkTarget = Join-Path $desktop'));
    expect(script, contains(r'$aabTarget = Join-Path $desktop'));
    expect(script, contains("\$androidVersion = '1.0.6'"));
    expect(script, contains(r'$androidVersionCode = 10006'));
    expect(script, contains("[ValidateSet('mobile', 'tvTest')]"));
    expect(script, contains(r"[string]$Flavor = 'mobile'"));
    expect(script, contains(r'[switch]$ApkOnly'));
    expect(script, contains('[char]0x770B'));
    expect(script, contains('com.kanyingyin.player'));
    expect(
      File('tool/android/build_tv_test.ps1').readAsStringSync(),
      contains(r'& $script -Flavor tvTest -ApkOnly'),
    );
  });

  test('Android Gradle 版本正则严格校验 fixture', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final patternSource = RegExp(
      r'val pubspecVersionPattern\s*=\s*Regex\("""([^"\r\n]+)"""\)',
    ).firstMatch(gradle)?.group(1);

    expect(patternSource, isNotNull);
    final pattern = RegExp(patternSource!);
    final valid = pattern.firstMatch('version: 9.8.7+90807');
    expect(valid, isNotNull);
    expect(valid!.group(1), '9.8.7');
    expect(valid.group(2), '90807');
    for (final invalid in <String>[
      'version: 9.8.7',
      'version: 9.8.7+0',
      ' version: 9.8.7+90807',
      'version: 9.8.7+90807 # comment',
      'version: 9.8+90807',
    ]) {
      expect(pattern.hasMatch(invalid), isFalse, reason: invalid);
    }
  });

  test(
    'Android 发布脚本严格解析版本 fixture',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'android_version_fixture_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final fixture = File(
        '${tempDirectory.path}${Platform.pathSeparator}pubspec.yaml',
      );
      final script = File(
        'tool/android/build_signed_release.ps1',
      ).absolute.path;

      Future<ProcessResult> parse(String source) async {
        await fixture.writeAsString(source, encoding: utf8, flush: true);
        return Process.run(
          'powershell.exe',
          <String>[
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            script,
            '-VersionOnly',
            '-VersionFixturePath',
            fixture.path,
          ],
        );
      }

      final valid = await parse('version: 9.8.7+90807\n');
      expect(valid.exitCode, 0, reason: valid.stderr.toString());
      expect(valid.stdout.toString().trim(), '9.8.7+90807');
      for (final invalid in <String>[
        'version: 9.8.7\n',
        'version: 9.8.7+0\n',
        ' version: 9.8.7+90807\n',
        'version: 9.8.7+90807 # comment\n',
        'version: 9.8.7+90807\nversion: 9.8.8+90808\n',
        'version: 9.8.7+2100000001\n',
        'version: 9.8.7+999999999999999999999\n',
      ]) {
        final result = await parse(invalid);
        expect(result.exitCode, isNot(0), reason: invalid);
      }
    },
    skip: !Platform.isWindows,
  );

  test('Android 发布验证四个源 JAR 和 Flutter 支持 ABI 的 Full libmpv', () {
    final verifier = File(
      'tool/android/verify_full_media_bundle.ps1',
    ).readAsStringSync();
    final release = File(
      'tool/android/build_signed_release.ps1',
    ).readAsStringSync();

    for (final sourceAbi in const <String>[
      'arm64-v8a',
      'armeabi-v7a',
      'x86',
      'x86_64',
    ]) {
      expect(verifier, contains(sourceAbi));
    }
    final packageAbis = RegExp(
      r'\$packageAbis\s*=\s*@\(([\s\S]*?)\)',
    ).firstMatch(verifier)?.group(1);
    expect(packageAbis, isNotNull);
    for (final packageAbi in const <String>[
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
    ]) {
      expect(packageAbis, contains("'$packageAbi'"));
    }
    expect(packageAbis, isNot(contains("'x86'")));
    expect(verifier, contains('foreach (\$abi in \$definitions.Keys)'));
    expect(verifier, contains('foreach (\$abi in \$packageAbis)'));
    expect(verifier, contains("ValidateSet('apk', 'aab')"));
    expect(verifier, contains("'base/lib'"));
    expect(verifier, contains("'lib'"));
    expect(verifier, contains('libmpv.so'));
    expect(verifier, contains('Get-FileHash'));
    expect(
      release,
      contains(
        "& \$fullBundleVerifier -PackagePath \$apk -PackageKind 'apk'",
      ),
    );
    expect(
      release,
      contains(
        "& \$fullBundleVerifier -PackagePath \$aab -PackageKind 'aab'",
      ),
    );
  });

  test('仓库忽略发布密钥且不包含实际密钥文件', () {
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore, contains('/android/key.properties'));
    expect(ignore, contains('*.jks'));
    expect(ignore, contains('*.keystore'));
    expect(ignore, contains('/tool/android/private-output/'));

    final trackedFiles = Process.runSync(
      'git',
      ['ls-files', '-z'],
      stdoutEncoding: null,
    );
    expect(trackedFiles.exitCode, 0);
    final keys =
        utf8.decode(trackedFiles.stdout as List<int>).split('\u0000').where(
              (path) => path.endsWith('.jks') || path.endsWith('.keystore'),
            );
    expect(keys, isEmpty);
  });
}
