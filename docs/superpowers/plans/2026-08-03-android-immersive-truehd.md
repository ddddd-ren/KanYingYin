# Android 沉浸式全屏与 TrueHD 解码 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个 Android 2.1.102 测试包，使只有 TrueHD/MLP 音轨的视频可软件解码并下混为立体声，同时让横屏播放器在焦点、旋转和前后台切换后继续保持彻底沉浸。

**Architecture:** 用仓库内本地 Flutter 插件覆盖 Android 的传递依赖，只替换为 media-kit 官方 Full v1.1.11 四 ABI 原生 JAR；Dart 播放器继续沿用现有 libmpv、MediaCodec 视频硬解和立体声降混路径。Android 原生侧把一次性系统栏操作拆成纯状态控制器与 Window 执行器，Activity 生命周期只负责重新应用已请求状态；构建脚本再逐 ABI 比对 APK/AAB 与 Full JAR 内的 `libmpv.so`，防止 Default 库混入交付包。

**Tech Stack:** Flutter 3.41.9、Dart、media-kit/libmpv、Android Kotlin/Java 17、Gradle/AGP、JUnit 4、PowerShell、MSIX/APK/AAB 签名工具。

---

## 实施边界

- 当前源码基线为 `2.1.101+20101`。Task 0 若发现源码或已安装 Windows 版本高于 `2.1.101`，停止版本修改并重新计算版本号；不要覆盖更高版本。
- Android TrueHD 输出固定为立体声 PCM，不实现 HDMI 原码直通或多声道 PCM。
- 不修改 `lib/pages/player/player_controller.dart` 的播放链路；现有 `audio-channels=stereo`、`ad-lavc-downmix=yes`、兼容音轨回退和视频硬解降级逻辑只由测试保护。
- 不重排播放器控件，不改 Flutter 全屏动画、方向策略、SafeArea、返回键或视频比例。
- Full v1.1.11 比当前 Predidit Default v1.2.5 更早，因此 Android 实机回归是正式采用的硬门槛。本轮文案必须保留“测试修复，待实机验证”。
- 本轮生成 Windows/Android 测试安装包并复制到桌面；不安装 Android APK、不安装新 MSIX、不推送 Git、不发布正式版本。

## 文件映射

### 新建

- `third_party/media_kit_libs_android_video_full/pubspec.yaml`：保持原 Flutter 插件名，供 `dependency_overrides` 替换 Android 传递依赖。
- `third_party/media_kit_libs_android_video_full/README.md`：记录 Full 资产来源、版本、用途与回滚方式。
- `third_party/media_kit_libs_android_video_full/LICENSE`：保留 media-kit MIT 许可证。
- `third_party/media_kit_libs_android_video_full/android/settings.gradle`：本地插件 Gradle 项目名。
- `third_party/media_kit_libs_android_video_full/android/build.gradle`：下载并校验四个 Full v1.1.11 JAR，构建失败时禁止回退。
- `third_party/media_kit_libs_android_video_full/android/src/main/AndroidManifest.xml`：保持 `extractNativeLibs` 契约。
- `third_party/media_kit_libs_android_video_full/android/src/main/java/com/alexmercerind/mediakitandroidhelper/MediaKitAndroidHelper.java`：保持 content URI/native helper 接口。
- `third_party/media_kit_libs_android_video_full/android/src/main/java/com/alexmercerind/media_kit_libs_android_video/MediaKitLibsAndroidVideoPlugin.java`：保持 media-kit 插件入口与 `libmpv` 加载。
- `lib/platform/android/android_media_bundle.dart`：暴露诊断标识 `full-v1.1.11`。
- `test/android_full_native_bundle_test.dart`：保护本地 override、Full URL、哈希和插件接口。
- `test/android_media_bundle_test.dart`：保护 Android 诊断标识且不污染 Windows 摘要。
- `tool/android/verify_full_media_bundle.ps1`：逐 ABI 比对 JAR、APK、AAB 中 `libmpv.so`。
- `android/app/src/main/kotlin/com/kanyingyin/player/ImmersiveModeController.kt`：保存沉浸请求状态，提供幂等重应用入口。
- `android/app/src/main/kotlin/com/kanyingyin/player/AndroidImmersiveModeApplier.kt`：负责系统栏、透明色、对比度和退出恢复。
- `android/app/src/test/kotlin/com/kanyingyin/player/ImmersiveModeControllerTest.kt`：原生状态控制器 JUnit 测试。

### 修改

- `pubspec.yaml`、`pubspec.lock`：启用 Android 本地 Full override，并在交付阶段更新到 `2.1.102+20102` / `2.1.102.0`。
- `lib/utils/diagnostic_log_exporter.dart`：在 Android 诊断摘要中加入 Full 包标识。
- `tool/android/build_signed_release.ps1`：对 APK/AAB 调用 Full 原生包验证，并同步版本。
- `android/app/build.gradle.kts`：加入 JUnit 4，并同步 Android 版本。
- `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt`：接入控制器，在恢复、焦点和配置变化时重应用。
- `test/android_player_media_compatibility_test.dart`：保护彻底沉浸契约和现有 TrueHD/视频硬解边界。
- `test/android_release_packaging_test.dart`：保护包内 Full 校验调用和 Android 版本。
- `lib/core/app_version.dart`、`lib/utils/version_history.dart`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`README.md`：同步 2.1.102 测试版和面向用户的谨慎文案。
- `test/release_config_contract_test.dart`、`test/version_consistency_test.dart`、`test/version_history_current_test.dart`、`test/identity_v2_zero_residue_test.dart`：同步版本与文案契约。

## Task 0: 记录环境与建立可回退基线

**Files:**
- Read only: `pubspec.yaml`
- Read only: `android/app/build.gradle.kts`
- Read only: 当前 Git 与 Windows 安装状态

- [ ] **Step 1: 固定 UTF-8 PowerShell 环境并记录 Windows 已安装版本**

Run:

```powershell
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
chcp 65001 > $null
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, PackageFullName, InstallLocation
```

Expected: 输出当前已安装版本；若无输出，明确记录“Windows 当前未安装”。若版本高于 `2.1.101.0`，停止后续版本替换并先修订本计划中的 `2.1.102/20102`。

- [ ] **Step 2: 确认源码、工具链和工作区状态**

Run:

```powershell
git status --short
git log -3 --oneline
& 'D:\flutter\bin\flutter.bat' --version
Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:|^\s*msix_version:' -Encoding UTF8
```

Expected: 工作区没有意外改动；Flutter 为 `3.41.9`；源码为 `2.1.101+20101`，MSIX 为 `2.1.101.0`。发现用户改动时保留并重新评估重叠文件，不得回退。

- [ ] **Step 3: 运行相关基线测试**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/android_player_media_compatibility_test.dart `
  test/android_release_packaging_test.dart `
  test/diagnostic_log_exporter_test.dart `
  test/truehd_fallback_policy_test.dart
Push-Location android
try {
  .\gradlew.bat :app:testDebugUnitTest --no-daemon
} finally {
  Pop-Location
}
```

Expected: 两条命令均通过。若基线失败，先区分既有失败与本轮范围，记录证据后再继续。

## Task 1: 引入官方 Full Android 原生媒体包

**Files:**
- Create: `test/android_full_native_bundle_test.dart`
- Create: `test/android_media_bundle_test.dart`
- Create: `third_party/media_kit_libs_android_video_full/**`
- Create: `lib/platform/android/android_media_bundle.dart`
- Modify: `pubspec.yaml:90-97`
- Modify: `pubspec.lock`
- Modify: `lib/utils/diagnostic_log_exporter.dart:3-10,106-113`

- [ ] **Step 1: 先写 Full 依赖与诊断标识的失败测试**

Create `test/android_full_native_bundle_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const assets = <String, String>{
    'full-arm64-v8a.jar':
        'cdb54c5cf24725623ca717bbbd6d991031d625a377460bd128f19c2dffe189bd',
    'full-armeabi-v7a.jar':
        'b658f2ff91169f8dad0e09e0240ebe200bb3df999da5712f8fab96ad11a4fbec',
    'full-x86.jar':
        '8b3b84e54ec09bb79972095dc04bcaf651294da4e73b1e7c3251055fd8a2b901',
    'full-x86_64.jar':
        '848936cfd7333077f21759adaca4a9e1a5647891da2e42ab211c5bdc30f4535d',
  };

  test('Android 使用仓库内官方 Full v1.1.11 原生包', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File(
      'third_party/media_kit_libs_android_video_full/android/build.gradle',
    ).readAsStringSync();

    expect(
      pubspec,
      contains(
        'media_kit_libs_android_video:\n'
        '    path: third_party/media_kit_libs_android_video_full',
      ),
    );
    expect(
      gradle,
      contains(
        'https://github.com/media-kit/libmpv-android-video-build/'
        'releases/download/v1.1.11/',
      ),
    );
    for (final asset in assets.entries) {
      expect(gradle, contains(asset.key));
      expect(gradle, contains(asset.value));
    }
    expect(gradle, isNot(contains('default-')));
  });

  test('本地适配包保持 media-kit Android 插件接口', () {
    final pubspec = File(
      'third_party/media_kit_libs_android_video_full/pubspec.yaml',
    ).readAsStringSync();
    final manifest = File(
      'third_party/media_kit_libs_android_video_full/'
      'android/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final plugin = File(
      'third_party/media_kit_libs_android_video_full/android/src/main/java/'
      'com/alexmercerind/media_kit_libs_android_video/'
      'MediaKitLibsAndroidVideoPlugin.java',
    ).readAsStringSync();
    final helper = File(
      'third_party/media_kit_libs_android_video_full/android/src/main/java/'
      'com/alexmercerind/mediakitandroidhelper/MediaKitAndroidHelper.java',
    ).readAsStringSync();

    expect(pubspec, contains('name: media_kit_libs_android_video'));
    expect(pubspec, contains('pluginClass: MediaKitLibsAndroidVideoPlugin'));
    expect(manifest, contains('android:extractNativeLibs="true"'));
    expect(plugin, contains('System.loadLibrary("mpv")'));
    expect(helper, contains('openFileDescriptorJava'));
  });
}
```

Create `test/android_media_bundle_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/android/android_media_bundle.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Android 诊断摘要标记 Full 原生媒体包', () {
    expect(
      AndroidMediaBundle.diagnosticLines(AppPlatformCapabilities.android),
      equals(const <String>['Android 原生媒体包: full-v1.1.11']),
    );
  });

  test('Windows 诊断摘要不声明 Android 原生媒体包', () {
    expect(
      AndroidMediaBundle.diagnosticLines(AppPlatformCapabilities.windows),
      isEmpty,
    );
  });

  test('诊断导出器接入平台原生媒体包标识', () {
    final exporter = File(
      'lib/utils/diagnostic_log_exporter.dart',
    ).readAsStringSync();

    expect(
      exporter,
      contains('...AndroidMediaBundle.diagnosticLines(platform)'),
    );
  });
}
```

- [ ] **Step 2: 运行测试并确认红灯来自缺失适配包与标识类**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/android_full_native_bundle_test.dart `
  test/android_media_bundle_test.dart
```

Expected: FAIL，原因分别为本地插件文件不存在、`android_media_bundle.dart` 无法导入；不能把其他编译错误当作预期失败。

- [ ] **Step 3: 创建本地 Flutter 插件元数据和说明**

Create `third_party/media_kit_libs_android_video_full/pubspec.yaml`:

```yaml
name: media_kit_libs_android_video
description: Android Full native libraries pinned for KanYingYin TrueHD playback.
version: 1.3.6
publish_to: none

environment:
  sdk: ">=2.17.0 <4.0.0"
  flutter: ">=3.3.0"

dependencies:
  flutter:
    sdk: flutter
  plugin_platform_interface: ^2.0.2

flutter:
  plugin:
    platforms:
      android:
        package: com.alexmercerind.media_kit_libs_android_video
        pluginClass: MediaKitLibsAndroidVideoPlugin
```

Create `third_party/media_kit_libs_android_video_full/README.md`:

```markdown
# media_kit_libs_android_video Full 适配包

本目录只覆盖看影音的 Android 原生媒体依赖。插件接口来自项目固定的
Predidit/media-kit 提交 `21aacaf9600c4bd00f2a3c57310363bc0cc9597f`，原生 JAR 固定为
media-kit/libmpv-android-video-build `v1.1.11` 的四个 Full 资产。

每个 JAR 在 Gradle 下载阶段校验 SHA-256。Android 发布脚本还会比较 JAR、APK 和
AAB 内各 ABI 的 `libmpv.so`。删除根 `pubspec.yaml` 中的 override 即可恢复传递依赖。
```

Create `third_party/media_kit_libs_android_video_full/android/settings.gradle`:

```groovy
rootProject.name = 'media_kit_libs_android_video'
```

Create `third_party/media_kit_libs_android_video_full/android/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
  package="com.alexmercerind.media_kit_libs_android_video">
  <application android:extractNativeLibs="true" />
</manifest>
```

Copy the pinned upstream license byte-for-byte:

```powershell
$source = 'C:\Users\asus\AppData\Local\Pub\Cache\git\media-kit-21aacaf9600c4bd00f2a3c57310363bc0cc9597f\libs\android\media_kit_libs_android_video\LICENSE'
$target = 'third_party\media_kit_libs_android_video_full\LICENSE'
Copy-Item -LiteralPath $source -Destination $target
```

- [ ] **Step 4: 创建保持 native helper ABI 的 Java 文件**

Create `third_party/media_kit_libs_android_video_full/android/src/main/java/com/alexmercerind/mediakitandroidhelper/MediaKitAndroidHelper.java`:

```java
package com.alexmercerind.mediakitandroidhelper;

import android.content.Context;
import android.net.Uri;
import androidx.annotation.Keep;

@Keep
public final class MediaKitAndroidHelper {
    static {
        System.loadLibrary("mediakitandroidhelper");
    }

    private static Context applicationContext;

    private MediaKitAndroidHelper() {}

    public static native long newGlobalObjectRef(Object object);

    public static native void deleteGlobalObjectRef(long reference);

    public static native String copyAssetToFilesDir(String assetName);

    private static native void setApplicationContextNative(Context context);

    public static void setApplicationContextJava(Context context) {
        applicationContext = context;
        setApplicationContextNative(context);
    }

    public static native int openFileDescriptorNative(String uri);

    public static int openFileDescriptorJava(String uri) {
        try {
            final Uri object = Uri.parse(uri);
            return applicationContext
                .getContentResolver()
                .openFileDescriptor(object, "r")
                .detachFd();
        } catch (Throwable error) {
            error.printStackTrace();
            return -1;
        }
    }
}
```

Create `third_party/media_kit_libs_android_video_full/android/src/main/java/com/alexmercerind/media_kit_libs_android_video/MediaKitLibsAndroidVideoPlugin.java`:

```java
package com.alexmercerind.media_kit_libs_android_video;

import android.util.Log;
import androidx.annotation.NonNull;
import com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

public final class MediaKitLibsAndroidVideoPlugin implements FlutterPlugin {
    static {
        try {
            System.loadLibrary("mpv");
        } catch (Throwable error) {
            error.printStackTrace();
        }
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        Log.i("media_kit", "package:media_kit_libs_android_video attached.");
        try {
            MediaKitAndroidHelper.setApplicationContextJava(
                binding.getApplicationContext()
            );
            Log.i("media_kit", "Saved application context.");
        } catch (Throwable error) {
            error.printStackTrace();
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        Log.i("media_kit", "package:media_kit_libs_android_video detached.");
    }
}
```

- [ ] **Step 5: 创建只接受四个 Full 资产的 Gradle 下载任务**

Create `third_party/media_kit_libs_android_video_full/android/build.gradle`:

```groovy
import java.nio.file.Files
import java.security.MessageDigest

group 'com.alexmercerind.media_kit_libs_android_video'
version '1.0'

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.13.0'
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply plugin: 'com.android.library'

android {
    namespace 'com.alexmercerind.media_kit_libs_android_video'
    compileSdkVersion 36

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    defaultConfig {
        minSdkVersion 16
    }
}

dependencies {
    implementation fileTree(dir: "$buildDir/output", include: ['*.jar'])
}

def downloadDependencies = tasks.register('downloadDependencies') {
    doLast {
        def outputDir = file("$buildDir/output")
        if (outputDir.exists()) {
            outputDir.deleteDir()
        }
        outputDir.mkdirs()

        def filesToDownload = [
            [
                url: 'https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.11/full-arm64-v8a.jar',
                sha256: 'cdb54c5cf24725623ca717bbbd6d991031d625a377460bd128f19c2dffe189bd',
                destination: file("$buildDir/v1.1.11/full-arm64-v8a.jar"),
            ],
            [
                url: 'https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.11/full-armeabi-v7a.jar',
                sha256: 'b658f2ff91169f8dad0e09e0240ebe200bb3df999da5712f8fab96ad11a4fbec',
                destination: file("$buildDir/v1.1.11/full-armeabi-v7a.jar"),
            ],
            [
                url: 'https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.11/full-x86.jar',
                sha256: '8b3b84e54ec09bb79972095dc04bcaf651294da4e73b1e7c3251055fd8a2b901',
                destination: file("$buildDir/v1.1.11/full-x86.jar"),
            ],
            [
                url: 'https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.11/full-x86_64.jar',
                sha256: '848936cfd7333077f21759adaca4a9e1a5647891da2e42ab211c5bdc30f4535d',
                destination: file("$buildDir/v1.1.11/full-x86_64.jar"),
            ],
        ]

        filesToDownload.each { fileInfo ->
            def destination = fileInfo.destination
            if (destination.exists()) {
                def cachedHash = MessageDigest.getInstance('SHA-256')
                    .digest(Files.readAllBytes(destination.toPath()))
                    .encodeHex()
                    .toString()
                if (cachedHash != fileInfo.sha256) {
                    destination.delete()
                }
            }

            if (!destination.exists()) {
                destination.parentFile.mkdirs()
                destination.withOutputStream { output ->
                    new URL(fileInfo.url).withInputStream { input ->
                        output << input
                    }
                }
            }

            def downloadedHash = MessageDigest.getInstance('SHA-256')
                .digest(Files.readAllBytes(destination.toPath()))
                .encodeHex()
                .toString()
            if (downloadedHash != fileInfo.sha256) {
                destination.delete()
                throw new GradleException(
                    "SHA-256 verification failed for ${destination}",
                )
            }

            copy {
                from destination
                into outputDir
            }
        }
    }
}

tasks.named('preBuild').configure {
    dependsOn(downloadDependencies)
}
```

- [ ] **Step 6: 启用本地 override 并刷新锁文件**

Add under `dependency_overrides` in `pubspec.yaml`:

```yaml
  media_kit_libs_android_video:
    path: third_party/media_kit_libs_android_video_full
```

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' pub get
& 'D:\flutter\bin\flutter.bat' pub deps --style=compact |
  Select-String 'media_kit_libs_android_video'
```

Expected: `pub get` 成功，依赖树显示 `media_kit_libs_android_video 1.3.6` 来自本地 override；`pubspec.lock` 不再把该包锁定到 Git 子路径。

- [ ] **Step 7: 加入 Android 原生包诊断标识**

Create `lib/platform/android/android_media_bundle.dart`:

```dart
import 'package:kanyingyin/platform/app_platform.dart';

abstract final class AndroidMediaBundle {
  static const String diagnosticLabel = 'full-v1.1.11';

  static List<String> diagnosticLines(AppPlatformCapabilities platform) {
    if (!platform.isAndroid) return const <String>[];
    return const <String>[
      'Android 原生媒体包: $diagnosticLabel',
    ];
  }
}
```

Add the import and diagnostic line expansion to `lib/utils/diagnostic_log_exporter.dart`:

```dart
import 'package:kanyingyin/platform/android/android_media_bundle.dart';
```

```dart
    final platform = detectAppPlatform();
    return <String>[
      '应用版本: ${AppVersion.current}',
      '系统版本: ${Platform.operatingSystemVersion}',
      '处理器架构: ${Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '未知'}',
      '硬件解码: $hardwareEnabled',
      '解码器: $decoder',
      ...AndroidMediaBundle.diagnosticLines(platform),
      '生成时间: ${DateTime.now().toIso8601String()}',
    ].join('\n');
```

- [ ] **Step 8: 格式化并运行 Task 1 测试**

Run:

```powershell
& 'D:\flutter\bin\dart.bat' format `
  lib/platform/android/android_media_bundle.dart `
  lib/utils/diagnostic_log_exporter.dart `
  test/android_full_native_bundle_test.dart `
  test/android_media_bundle_test.dart
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/android_full_native_bundle_test.dart `
  test/android_media_bundle_test.dart `
  test/diagnostic_log_exporter_test.dart `
  test/android_player_media_compatibility_test.dart
```

Expected: 全部 PASS；Windows 诊断测试不出现 Android Full 标识，播放器兼容测试仍确认 TrueHD 立体声降混与视频硬解边界。

- [ ] **Step 9: 审阅并提交 Full 依赖变更**

Run:

```powershell
git diff --check
git status --short
git diff -- pubspec.yaml pubspec.lock lib/utils/diagnostic_log_exporter.dart `
  lib/platform/android/android_media_bundle.dart `
  third_party/media_kit_libs_android_video_full `
  test/android_full_native_bundle_test.dart test/android_media_bundle_test.dart
git add pubspec.yaml pubspec.lock lib/utils/diagnostic_log_exporter.dart `
  lib/platform/android/android_media_bundle.dart `
  third_party/media_kit_libs_android_video_full `
  test/android_full_native_bundle_test.dart test/android_media_bundle_test.dart
git commit -m '功能：为安卓启用Full媒体解码库'
```

Expected: 提交只包含 Task 1 文件，未提交构建缓存或用户文件。

## Task 2: 验证 APK/AAB 确实包含 Full libmpv

**Files:**
- Create: `tool/android/verify_full_media_bundle.ps1`
- Modify: `test/android_release_packaging_test.dart:33-57`
- Modify: `tool/android/build_signed_release.ps1:65-104`

- [ ] **Step 1: 先为发布脚本写失败契约**

Append to `test/android_release_packaging_test.dart`:

```dart
  test('Android 发布逐 ABI 验证 APK 和 AAB 的 Full libmpv', () {
    final verifier = File(
      'tool/android/verify_full_media_bundle.ps1',
    ).readAsStringSync();
    final release = File(
      'tool/android/build_signed_release.ps1',
    ).readAsStringSync();

    for (final abi in const <String>[
      'arm64-v8a',
      'armeabi-v7a',
      'x86',
      'x86_64',
    ]) {
      expect(verifier, contains(abi));
    }
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
```

- [ ] **Step 2: 运行测试并确认 verifier 文件缺失导致失败**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/android_release_packaging_test.dart
```

Expected: FAIL，原因是 `tool/android/verify_full_media_bundle.ps1` 不存在。

- [ ] **Step 3: 实现逐 ABI 嵌套 ZIP 哈希校验器**

Create `tool/android/verify_full_media_bundle.ps1`:

```powershell
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('apk', 'aab')]
  [string]$PackageKind,

  [Parameter(Mandatory = $true)]
  [string]$PackagePath,

  [string]$NativeCacheRoot = ''
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
chcp 65001 > $null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($NativeCacheRoot)) {
  $NativeCacheRoot = Join-Path $projectRoot `
    'build\media_kit_libs_android_video\v1.1.11'
}

function Get-ZipEntrySha256 {
  param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [Parameter(Mandatory = $true)][string]$EntryName
  )

  $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $entry = $archive.GetEntry($EntryName)
    if ($null -eq $entry) {
      throw "压缩包缺少条目：$ZipPath -> $EntryName"
    }
    $stream = $entry.Open()
    try {
      $sha256 = [System.Security.Cryptography.SHA256]::Create()
      try {
        $hash = $sha256.ComputeHash($stream)
      } finally {
        $sha256.Dispose()
      }
    } finally {
      $stream.Dispose()
    }
  } finally {
    $archive.Dispose()
  }
  return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

$definitions = [ordered]@{
  'arm64-v8a' = [ordered]@{
    Jar = 'full-arm64-v8a.jar'
    Sha256 = 'cdb54c5cf24725623ca717bbbd6d991031d625a377460bd128f19c2dffe189bd'
  }
  'armeabi-v7a' = [ordered]@{
    Jar = 'full-armeabi-v7a.jar'
    Sha256 = 'b658f2ff91169f8dad0e09e0240ebe200bb3df999da5712f8fab96ad11a4fbec'
  }
  'x86' = [ordered]@{
    Jar = 'full-x86.jar'
    Sha256 = '8b3b84e54ec09bb79972095dc04bcaf651294da4e73b1e7c3251055fd8a2b901'
  }
  'x86_64' = [ordered]@{
    Jar = 'full-x86_64.jar'
    Sha256 = '848936cfd7333077f21759adaca4a9e1a5647891da2e42ab211c5bdc30f4535d'
  }
}

$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$packagePrefix = if ($PackageKind -eq 'aab') { 'base/lib' } else { 'lib' }

foreach ($abi in $definitions.Keys) {
  $definition = $definitions[$abi]
  $jarPath = Join-Path $NativeCacheRoot $definition.Jar
  if (-not (Test-Path -LiteralPath $jarPath -PathType Leaf)) {
    throw "缺少 Full 原生 JAR：$jarPath"
  }
  $jarFileHash = (Get-FileHash -LiteralPath $jarPath -Algorithm SHA256).Hash
  if ($jarFileHash.ToLowerInvariant() -ne $definition.Sha256) {
    throw "Full 原生 JAR 哈希错误：$jarPath"
  }

  $jarEntry = "lib/$abi/libmpv.so"
  $packageEntry = "$packagePrefix/$abi/libmpv.so"
  $jarLibHash = Get-ZipEntrySha256 -ZipPath $jarPath -EntryName $jarEntry
  $packageLibHash = Get-ZipEntrySha256 `
    -ZipPath $resolvedPackage `
    -EntryName $packageEntry
  if ($jarLibHash -ne $packageLibHash) {
    throw "安装包中的 $abi/libmpv.so 不是固定 Full 资产"
  }
  Write-Output "Full libmpv verified: $PackageKind / $abi / $packageLibHash"
}
```

- [ ] **Step 4: 将验证器接入签名发布脚本**

Insert immediately after APK/AAB existence checks in `tool/android/build_signed_release.ps1`:

```powershell
    $fullBundleVerifier = Join-Path $PSScriptRoot 'verify_full_media_bundle.ps1'
    & $fullBundleVerifier -PackagePath $apk -PackageKind 'apk'
    & $fullBundleVerifier -PackagePath $aab -PackageKind 'aab'
```

The verification must run before copying either artifact to the desktop. A thrown hash or missing-entry error terminates the release script because `$ErrorActionPreference = 'Stop'`.

- [ ] **Step 5: 运行契约测试和 PowerShell 语法检查**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/android_release_packaging_test.dart `
  test/android_full_native_bundle_test.dart
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path 'tool\android\verify_full_media_bundle.ps1'),
  [ref]$null,
  [ref]$errors
) | Out-Null
if ($errors.Count -ne 0) { $errors; throw 'PowerShell 语法检查失败' }
```

Expected: Flutter 测试 PASS，PowerShell 解析错误数为 0。

- [ ] **Step 6: 审阅并提交包级验证**

Run:

```powershell
git diff --check
git diff -- tool/android/verify_full_media_bundle.ps1 `
  tool/android/build_signed_release.ps1 `
  test/android_release_packaging_test.dart
git add tool/android/verify_full_media_bundle.ps1 `
  tool/android/build_signed_release.ps1 `
  test/android_release_packaging_test.dart
git commit -m '构建：验证安卓Full原生媒体库'
```

Expected: 提交不含安装包、下载缓存或签名信息。

## Task 3: 用单元测试固化沉浸请求状态

**Files:**
- Create: `android/app/src/test/kotlin/com/kanyingyin/player/ImmersiveModeControllerTest.kt`
- Create: `android/app/src/main/kotlin/com/kanyingyin/player/ImmersiveModeController.kt`
- Modify: `android/app/build.gradle.kts:76-80`

- [ ] **Step 1: 加入 JUnit 4 依赖并写状态控制器失败测试**

Add to `android/app/build.gradle.kts` after the `android` block:

```kotlin
dependencies {
    testImplementation("junit:junit:4.13.2")
}
```

Create `android/app/src/test/kotlin/com/kanyingyin/player/ImmersiveModeControllerTest.kt`:

```kotlin
package com.kanyingyin.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImmersiveModeControllerTest {
    @Test
    fun enablingStoresRequestAndAppliesImmersiveMode() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled ->
            calls += enabled
        }

        controller.setEnabled(true)

        assertTrue(controller.isRequested)
        assertEquals(listOf(true), calls)
    }

    @Test
    fun lifecycleReapplyRunsOnlyWhileImmersiveIsRequested() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled ->
            calls += enabled
        }

        controller.reapplyIfRequested()
        controller.setEnabled(true)
        controller.reapplyIfRequested()

        assertEquals(listOf(true, true), calls)
    }

    @Test
    fun disablingRestoresBarsAndStopsFutureReapply() {
        val calls = mutableListOf<Boolean>()
        val controller = ImmersiveModeController { enabled ->
            calls += enabled
        }

        controller.setEnabled(true)
        controller.setEnabled(false)
        controller.reapplyIfRequested()

        assertFalse(controller.isRequested)
        assertEquals(listOf(true, false), calls)
    }
}
```

- [ ] **Step 2: 运行原生测试并确认控制器缺失导致失败**

Run:

```powershell
Push-Location android
try {
  .\gradlew.bat :app:testDebugUnitTest `
    --tests 'com.kanyingyin.player.ImmersiveModeControllerTest' `
    --no-daemon
} finally {
  Pop-Location
}
```

Expected: FAIL，Kotlin 编译提示 `ImmersiveModeController` 未定义。

- [ ] **Step 3: 实现最小纯状态控制器**

Create `android/app/src/main/kotlin/com/kanyingyin/player/ImmersiveModeController.kt`:

```kotlin
package com.kanyingyin.player

internal fun interface ImmersiveModeApplier {
    fun apply(enabled: Boolean)
}

internal class ImmersiveModeController(
    private val applier: ImmersiveModeApplier,
) {
    var isRequested: Boolean = false
        private set

    fun setEnabled(enabled: Boolean) {
        isRequested = enabled
        applier.apply(enabled)
    }

    fun reapplyIfRequested() {
        if (isRequested) {
            applier.apply(true)
        }
    }
}
```

- [ ] **Step 4: 运行控制器测试并确认绿灯**

Run the same Gradle command from Step 2.

Expected: `3 tests completed`，全部 PASS。

- [ ] **Step 5: 审阅并提交状态控制器**

Run:

```powershell
git diff --check
git diff -- android/app/build.gradle.kts `
  android/app/src/main/kotlin/com/kanyingyin/player/ImmersiveModeController.kt `
  android/app/src/test/kotlin/com/kanyingyin/player/ImmersiveModeControllerTest.kt
git add android/app/build.gradle.kts `
  android/app/src/main/kotlin/com/kanyingyin/player/ImmersiveModeController.kt `
  android/app/src/test/kotlin/com/kanyingyin/player/ImmersiveModeControllerTest.kt
git commit -m '功能：记录安卓沉浸全屏状态'
```

Expected: 只提交控制器、测试和 JUnit 依赖。

## Task 4: 实现可恢复的彻底沉浸系统栏

**Files:**
- Create: `android/app/src/main/kotlin/com/kanyingyin/player/AndroidImmersiveModeApplier.kt`
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt:18-20,28-46,353-378`
- Modify: `test/android_player_media_compatibility_test.dart:5-20,100-121`

- [ ] **Step 1: 为系统栏和生命周期写失败契约**

Extend `setUpAll` in `test/android_player_media_compatibility_test.dart` with:

```dart
    immersiveModeController = File(
      'android/app/src/main/kotlin/com/kanyingyin/player/'
      'ImmersiveModeController.kt',
    ).readAsStringSync();
    immersiveModeApplier = File(
      'android/app/src/main/kotlin/com/kanyingyin/player/'
      'AndroidImmersiveModeApplier.kt',
    ).readAsStringSync();
```

Declare the two `late String` fields beside the existing source fields, then add:

```dart
  test('Android 全屏保持彻底沉浸并在退出时恢复系统栏', () {
    expect(immersiveModeController, contains('var isRequested: Boolean'));
    expect(
      immersiveModeApplier,
      contains('BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE'),
    );
    expect(
      immersiveModeApplier,
      contains('window.setDecorFitsSystemWindows(false)'),
    );
    expect(immersiveModeApplier, contains('Color.TRANSPARENT'));
    expect(
      immersiveModeApplier,
      contains('window.isNavigationBarContrastEnforced = false'),
    );
    expect(
      immersiveModeApplier,
      contains('controller.hide(WindowInsets.Type.systemBars())'),
    );
    expect(
      immersiveModeApplier,
      contains('window.setDecorFitsSystemWindows(true)'),
    );
    expect(
      immersiveModeApplier,
      contains('controller.show(WindowInsets.Type.systemBars())'),
    );
    expect(mainActivity, contains('override fun onResume()'));
    expect(mainActivity, contains('override fun onWindowFocusChanged'));
    expect(mainActivity, contains('immersiveModeController.reapplyIfRequested()'));
    expect(mainActivity, contains('immersiveModeController.setEnabled(enabled)'));
    expect(windowUtils, contains('setImmersive(true)'));
    expect(windowUtils, contains('setImmersive(false)'));
  });

  test('Android TrueHD 无兼容音轨时保持视频并提示导出日志', () {
    expect(
      controller,
      contains('当前播放器组件无法解码此音轨，请导出诊断日志'),
    );
    expect(controller, contains('_truehdAudioTrackFallbackAttempted = true'));
    expect(controller, isNot(contains('_retryWithSoftwareDecodingForTrueHd')));
  });
```

- [ ] **Step 2: 运行兼容测试并确认执行器缺失导致失败**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/android_player_media_compatibility_test.dart
```

Expected: FAIL，原因是 `AndroidImmersiveModeApplier.kt` 不存在。

- [ ] **Step 3: 实现系统栏执行器和退出恢复**

Create `android/app/src/main/kotlin/com/kanyingyin/player/AndroidImmersiveModeApplier.kt`:

```kotlin
package com.kanyingyin.player

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowInsets
import android.view.WindowInsetsController

@Suppress("DEPRECATION")
internal class AndroidImmersiveModeApplier(
    activity: Activity,
) : ImmersiveModeApplier {
    private val window: Window = activity.window
    private var savedState: SavedSystemBarState? = null

    override fun apply(enabled: Boolean) {
        if (enabled) {
            enableImmersiveMode()
        } else {
            disableImmersiveMode()
        }
    }

    private fun enableImmersiveMode() {
        if (savedState == null) {
            savedState = captureState()
        }
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let { controller ->
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                controller.setSystemBarsAppearance(0, lightBarAppearanceMask)
                controller.hide(WindowInsets.Type.systemBars())
            }
        } else {
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
    }

    private fun disableImmersiveMode() {
        val state = savedState
        if (state != null) {
            window.statusBarColor = state.statusBarColor
            window.navigationBarColor = state.navigationBarColor
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                window.isStatusBarContrastEnforced =
                    state.statusBarContrastEnforced ?: true
                window.isNavigationBarContrastEnforced =
                    state.navigationBarContrastEnforced ?: true
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(true)
            window.insetsController?.let { controller ->
                state?.systemBarsAppearance?.let { appearance ->
                    controller.setSystemBarsAppearance(
                        appearance,
                        lightBarAppearanceMask,
                    )
                }
                controller.show(WindowInsets.Type.systemBars())
            }
        } else {
            window.decorView.systemUiVisibility =
                state?.systemUiVisibility ?: View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
        savedState = null
    }

    private fun captureState(): SavedSystemBarState {
        val controller = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController
        } else {
            null
        }
        return SavedSystemBarState(
            statusBarColor = window.statusBarColor,
            navigationBarColor = window.navigationBarColor,
            systemUiVisibility = window.decorView.systemUiVisibility,
            statusBarContrastEnforced =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    window.isStatusBarContrastEnforced
                } else {
                    null
                },
            navigationBarContrastEnforced =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    window.isNavigationBarContrastEnforced
                } else {
                    null
                },
            systemBarsAppearance =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    controller?.systemBarsAppearance
                } else {
                    null
                },
        )
    }

    private data class SavedSystemBarState(
        val statusBarColor: Int,
        val navigationBarColor: Int,
        val systemUiVisibility: Int,
        val statusBarContrastEnforced: Boolean?,
        val navigationBarContrastEnforced: Boolean?,
        val systemBarsAppearance: Int?,
    )

    private companion object {
        val lightBarAppearanceMask =
            WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
    }
}
```

- [ ] **Step 4: 将 MainActivity 接到状态控制器和三个恢复点**

Remove the old `View`, `WindowInsets`, and `WindowInsetsController` imports from `MainActivity.kt`. Add the controller property inside `MainActivity`:

```kotlin
    private val immersiveModeController by lazy {
        ImmersiveModeController(AndroidImmersiveModeApplier(this))
    }
```

Replace the lifecycle block with:

```kotlin
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyTabletLandscapePolicy(resources.configuration)
    }

    override fun onResume() {
        super.onResume()
        immersiveModeController.reapplyIfRequested()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            immersiveModeController.reapplyIfRequested()
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyTabletLandscapePolicy(newConfig)
        immersiveModeController.reapplyIfRequested()
    }
```

Replace the old `handleSetImmersive` implementation with:

```kotlin
    private fun handleSetImmersive(enabled: Boolean, result: MethodChannel.Result) {
        immersiveModeController.setEnabled(enabled)
        result.success(null)
    }
```

- [ ] **Step 5: 运行 Kotlin 与 Flutter 契约测试**

Run:

```powershell
Push-Location android
try {
  .\gradlew.bat :app:testDebugUnitTest --no-daemon
} finally {
  Pop-Location
}
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/android_player_media_compatibility_test.dart `
  test/truehd_fallback_policy_test.dart
```

Expected: JUnit 和 Flutter 测试全部 PASS；原有平板方向、字幕、TrueHD 立体声降混、视频硬解回退契约继续通过。

- [ ] **Step 6: 确认没有改动 Flutter 控件层或播放链路**

Run:

```powershell
git status --short
git diff --name-only
git diff -- lib/pages/player/player_controller.dart lib/utils/window_utils.dart
```

Expected: 最后一条无输出；播放器 Dart 控制层与 `WindowUtils` 没有变化。

- [ ] **Step 7: 审阅并提交沉浸模式**

Run:

```powershell
git diff --check
git diff -- android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt `
  android/app/src/main/kotlin/com/kanyingyin/player/AndroidImmersiveModeApplier.kt `
  test/android_player_media_compatibility_test.dart
git add android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt `
  android/app/src/main/kotlin/com/kanyingyin/player/AndroidImmersiveModeApplier.kt `
  test/android_player_media_compatibility_test.dart
git commit -m '功能：保持安卓播放器彻底沉浸'
```

Expected: Task 3 的控制器提交保持独立；本提交只包含系统栏执行器、Activity 接线和契约测试。

## Task 5: 准备 2.1.102 双平台测试版文案与版本

**Files:**
- Modify: `pubspec.yaml:19,139`
- Modify: `android/app/build.gradle.kts:29-30`
- Modify: `tool/android/build_signed_release.ps1:10-11,49-50`
- Modify: `lib/core/app_version.dart:5`
- Modify: `lib/utils/version_history.dart:47-58,109-123,1916-1923`
- Modify: `RELEASE_NOTES.md:1-3`
- Modify: `UPDATE_DIALOG_COPY.md:3-35`
- Modify: `README.md:96-105`
- Modify: `test/android_release_packaging_test.dart`
- Modify: `test/release_config_contract_test.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 先把当前版本契约改为 2.1.102 并确认红灯**

Use these exact expected values in all current-version tests:

```dart
const expectedVersion = '2.1.102';
const expectedBuildNumber = '20102';
const expectedAndroidVersion = '2.1.102';
const expectedAndroidVersionCode = '20102';
```

Apply the following exact test-file mapping:

- `test/release_config_contract_test.dart`: rename the current release test to `当前发布配置固定为双平台二点一零二测试版` and replace `2.1.101+20101` / `2.1.101.0` / `2.1.101` with `2.1.102+20102` / `2.1.102.0` / `2.1.102` inside that test only.
- `test/version_consistency_test.dart`: rename the current test to `二点一零二测试版双平台版本和发布文案保持一致`, replace the four expected constants with the values above, and replace the current-copy keyword list with the list below plus `Windows` and `Android`.
- `test/android_release_packaging_test.dart`: replace only the current Gradle/script version literals with `2.1.102` and `20102`; retain the Full package verifier assertions.
- `test/identity_v2_zero_residue_test.dart`: set the expected current version/build to `2.1.102` / `20102`.
- `test/version_history_current_test.dart`: replace the first two current-version tests with the combined and Android-specific 2.1.102 assertions below; leave historical release tests unchanged.

Update the first two tests in `test/version_history_current_test.dart` to query `2.1.102` and require:

```dart
for (final text in <String>[
  'TrueHD',
  'Full',
  '立体声',
  '沉浸',
  '待实机验证',
  '测试版',
  '不会修改或删除',
]) {
  expect(changes, contains(text));
}
```

For the combined entry also require `Windows` and `Android`; for the Android-specific entry assert `changes` does not contain `Windows`. Update these literal checks elsewhere:

```dart
expect(pubspec, contains('version: 2.1.102+20102'));
expect(pubspec, contains('msix_version: 2.1.102.0'));
expect(gradle, contains('val androidVersionName = "2.1.102"'));
expect(gradle, contains('val androidVersionCode = 20102'));
expect(script, contains(r"$androidVersion = '2.1.102'"));
expect(script, contains(r'$androidVersionCode = 20102'));
expect(currentVersion, '2.1.102');
expect(packageVersion.group(2), '20102');
```

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/release_config_contract_test.dart `
  test/version_consistency_test.dart `
  test/version_history_current_test.dart `
  test/identity_v2_zero_residue_test.dart `
  test/android_release_packaging_test.dart
```

Expected: FAIL，所有失败均指向源码仍为 `2.1.101` 或缺少 2.1.102 文案。

- [ ] **Step 2: 同步机器可读版本字段**

Apply these exact values:

```yaml
version: 2.1.102+20102
```

```yaml
  msix_version: 2.1.102.0
```

```kotlin
val androidVersionName = "2.1.102"
val androidVersionCode = 20102
```

```dart
static const String current = '2.1.102';
```

```powershell
$androidVersion = '2.1.102'
$androidVersionCode = 20102
```

Also change the pubspec guard in `tool/android/build_signed_release.ps1` to:

```powershell
    if ($windowsVersion -ne '2.1.102' -or $windowsBuildNumber -ne '20102') {
        throw "Windows pubspec 版本必须为 2.1.102+20102，实际为 $windowsVersion+$windowsBuildNumber"
    }
```

- [ ] **Step 3: 加入 Android 专属和双平台版本历史**

Insert before the existing Android 2.1.101 constant in `lib/utils/version_history.dart`:

```dart
const VersionHistory _androidImmersiveTrueHdPrerelease = VersionHistory(
  version: '2.1.102',
  date: '2026-08-03',
  isPrerelease: true,
  changes: [
    'Android 2.1.102 测试版改用官方 Full 原生媒体包，为 TrueHD/MLP 音轨提供软件解码并下混为立体声；当前为测试修复，待实机验证',
    'TrueHD 音频解码继续保留 MediaCodec 视频硬件解码，不会为音轨重建或关闭视频硬解链路',
    '横屏播放器进入彻底沉浸模式，控制层显示时系统栏仍保持隐藏，边缘滑动可临时唤出',
    '旋转设备、切换后台再返回或窗口重新获得焦点后会恢复沉浸；退出播放器时恢复系统栏和原有方向策略',
    '诊断日志新增 full-v1.1.11 原生媒体包标识，便于确认实际安装的测试组件',
    '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
  ],
);
```

Insert at the start of `versionHistoryList`:

```dart
  VersionHistory(
    version: '2.1.102',
    date: '2026-08-03',
    isPrerelease: true,
    changes: [
      '本轮同步提供 Windows 与 Android 2.1.102 测试版，分别使用 MSIX、APK 和 AAB 交付',
      'Android 改用官方 Full 原生媒体包，为 TrueHD/MLP 音轨提供软件解码并下混为立体声；当前为测试修复，待实机验证',
      'TrueHD 音频解码继续保留 MediaCodec 视频硬件解码，不会为音轨重建或关闭视频硬解链路',
      'Android 横屏播放器进入彻底沉浸模式，并在旋转、恢复前台和重新获得焦点后继续隐藏系统栏',
      '诊断日志新增 full-v1.1.11 标识；Windows 播放器原生组件和播放行为保持不变',
      '本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件',
    ],
  ),
```

Add before the 2.1.101 Android branch in `versionHistoryForCurrent`:

```dart
  if (currentVersion == '2.1.102' &&
      platform == AppPlatformKind.android) {
    return const <VersionHistory>[_androidImmersiveTrueHdPrerelease];
  }
```

Keep every historical 2.1.101 entry unchanged.

- [ ] **Step 4: 写入面向用户的当前发布说明**

Insert this section immediately after the H1 in `RELEASE_NOTES.md`:

```markdown
## 2.1.102+20102

MSIX 版本：2.1.102.0

APK/AAB 版本：2.1.102 (20102)

### Windows 测试版更新内容

标题：看影音 2.1.102 测试版

- 本轮同步提供 Windows 与 Android 2.1.102 测试版，分别使用 MSIX、APK 和 AAB 交付。
- Android 改用官方 Full 原生媒体包，为 TrueHD/MLP 音轨提供软件解码并下混为立体声；当前为测试修复，待实机验证。
- TrueHD 音频解码继续保留 MediaCodec 视频硬件解码，不会为音轨重建或关闭视频硬解链路。
- Android 横屏播放器进入彻底沉浸模式，并在旋转、恢复前台和重新获得焦点后继续隐藏系统栏。
- 诊断日志新增 full-v1.1.11 标识；Windows 播放器原生组件和播放行为保持不变。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。

### Android 测试版更新内容

标题：看影音 Android 2.1.102 测试版

- Android 2.1.102 测试版改用官方 Full 原生媒体包，为 TrueHD/MLP 音轨提供软件解码并下混为立体声；当前为测试修复，待实机验证。
- TrueHD 音频解码继续保留 MediaCodec 视频硬件解码，不会为音轨重建或关闭视频硬解链路。
- 横屏播放器进入彻底沉浸模式，控制层显示时系统栏仍保持隐藏，边缘滑动可临时唤出。
- 旋转设备、切换后台再返回或窗口重新获得焦点后会恢复沉浸；退出播放器时恢复系统栏和原有方向策略。
- 诊断日志新增 full-v1.1.11 原生媒体包标识，便于确认实际安装的测试组件。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。
```

Replace the current-version block in `UPDATE_DIALOG_COPY.md`, while retaining its existing maintenance section, with:

```markdown
## 当前版本

- 应用版本：2.1.102
- 安装包版本：2.1.102.0
- 本轮交付：Windows 测试版 MSIX、Android 测试版 APK/AAB
- Android 应用版本：2.1.102
- Android versionCode：20102
- 日期：2026-08-03

## 弹窗标题

看影音 2.1.102 测试版

## Windows 弹窗正文

- 本轮同步提供 Windows 与 Android 2.1.102 测试版，分别使用 MSIX、APK 和 AAB 交付。
- Android 改用官方 Full 原生媒体包，为 TrueHD/MLP 音轨提供软件解码并下混为立体声；当前为测试修复，待实机验证。
- TrueHD 音频解码继续保留 MediaCodec 视频硬件解码，不会为音轨重建或关闭视频硬解链路。
- Android 横屏播放器进入彻底沉浸模式，并在旋转、恢复前台和重新获得焦点后继续隐藏系统栏。
- 诊断日志新增 full-v1.1.11 标识；Windows 播放器原生组件和播放行为保持不变。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。

## Android 弹窗正文

### 弹窗标题

看影音 Android 2.1.102 测试版

- Android 2.1.102 测试版改用官方 Full 原生媒体包，为 TrueHD/MLP 音轨提供软件解码并下混为立体声；当前为测试修复，待实机验证。
- TrueHD 音频解码继续保留 MediaCodec 视频硬件解码，不会为音轨重建或关闭视频硬解链路。
- 横屏播放器进入彻底沉浸模式，控制层显示时系统栏仍保持隐藏，边缘滑动可临时唤出。
- 旋转设备、切换后台再返回或窗口重新获得焦点后会恢复沉浸；退出播放器时恢复系统栏和原有方向策略。
- 诊断日志新增 full-v1.1.11 原生媒体包标识，便于确认实际安装的测试组件。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。

## 按钮文字

知道了
```

Update `README.md` to:

```markdown
| 当前版本 | 2.1.102 |
| 本轮交付 | Windows 测试版 MSIX；Android 测试版 APK/AAB |
| Android 版本 | 2.1.102 |
```

```markdown
项目同时支持 Windows 与 Android。2.1.102 本轮构建并交付 Windows 测试版 MSIX
和 Android 2.1.102 测试版签名 APK/AAB；APK 用于直接安装，AAB 用于 Android
应用商店交付。
```

- [ ] **Step 5: 格式化并运行版本契约**

Run:

```powershell
& 'D:\flutter\bin\dart.bat' format `
  lib/core/app_version.dart `
  lib/utils/version_history.dart `
  test/android_release_packaging_test.dart `
  test/release_config_contract_test.dart `
  test/version_consistency_test.dart `
  test/version_history_current_test.dart `
  test/identity_v2_zero_residue_test.dart
& 'D:\flutter\bin\flutter.bat' test --no-pub `
  test/release_config_contract_test.dart `
  test/version_consistency_test.dart `
  test/version_history_current_test.dart `
  test/identity_v2_zero_residue_test.dart `
  test/android_release_packaging_test.dart
```

Expected: 全部 PASS；所有当前版本入口为 2.1.102/20102，历史 2.1.101 仍可查询，测试版标识为真。

- [ ] **Step 6: 暂不提交版本文件，保留给完整交付门禁**

Run:

```powershell
git diff --check
git status --short
```

Expected: 只有 Task 5 的版本、文案和测试文件未提交；它们将在 Task 7 的安装包全部验证通过后一起提交。

## Task 6: 完整自动化与未签名 Android 包验证

**Files:**
- Verify: all changed source and tests
- Generate only: `build/**`

- [ ] **Step 1: 运行全部 Dart 测试**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub
```

Expected: 全量 PASS，无跳过本轮新增测试。

- [ ] **Step 2: 运行 Flutter 静态分析**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' analyze --no-pub
```

Expected: `No issues found!`，至少无 error；若仓库基线存在 warning，逐条确认不是本轮引入并记录。

- [ ] **Step 3: 运行全部 Android JVM 单元测试**

Run:

```powershell
Push-Location android
try {
  .\gradlew.bat :app:testDebugUnitTest --no-daemon
} finally {
  Pop-Location
}
```

Expected: BUILD SUCCESSFUL，沉浸控制器 3 个测试通过。

- [ ] **Step 4: 构建 Debug APK 以触发 Full 资产下载和打包**

Run:

```powershell
& 'D:\flutter\bin\flutter.bat' build apk --debug --no-pub
& 'tool\android\verify_full_media_bundle.ps1' `
  -PackageKind 'apk' `
  -PackagePath 'build\app\outputs\flutter-apk\app-debug.apk'
```

Expected: 四个 Full JAR 下载或复用缓存时均通过固定 SHA-256；Debug APK 的四个 `libmpv.so` 均与对应 Full JAR 一致。任何下载、条目或哈希失败都停止交付。

- [ ] **Step 5: 检查缓存与 Git 边界**

Run:

```powershell
Get-FileHash -Algorithm SHA256 `
  build\media_kit_libs_android_video\v1.1.11\full-*.jar |
  Select-Object Path, Hash
git status --short
git diff --check
```

Expected: 四个哈希与设计固定值一致；`build/**` 未进入 Git 状态；未提交改动仍只有 Task 5 版本文件。

## Task 7: 生成并验证 Windows/Android 测试安装包

**Files:**
- Verify: `tool/windows/build_signed_release.ps1`
- Verify: `tool/android/build_signed_release.ps1`
- Generate only: Windows Release、MSIX、APK、AAB 与桌面交付物
- Commit: Task 5 version and release-copy files

- [ ] **Step 1: 生成签名 Windows Release 和 MSIX**

Ensure the running app is closed, then run:

```powershell
& 'tool\windows\build_signed_release.ps1'
```

Expected: Windows Release 构建成功；MSIX 签名有效；清单 `Name=com.kanyingyin.player`、`Version=2.1.102.0`、`ProcessorArchitecture=x64`；桌面生成 `看影音-2.1.102.msix` 和 `看影音-2.1.102-异机安装包.zip`，源/桌面 MSIX 哈希一致。

- [ ] **Step 2: 生成签名 Android APK/AAB**

Run:

```powershell
& 'tool\android\build_signed_release.ps1'
```

Expected: APK 与 AAB Release 构建成功；APK v2 签名有效，AAB 严格 JAR 签名有效；包名 `com.kanyingyin.player`，`versionName=2.1.102`、`versionCode=20102`；脚本对 APK/AAB 各输出四条 `Full libmpv verified`；桌面生成 `看影音-2.1.102.apk` 和 `看影音-2.1.102.aab`。

- [ ] **Step 3: 独立复核桌面与构建目录哈希**

Run:

```powershell
$desktop = [Environment]::GetFolderPath('Desktop')
$pairs = @(
  @('build\windows\x64\runner\Release\kanyingyin.msix', (Join-Path $desktop '看影音-2.1.102.msix')),
  @('build\app\outputs\flutter-apk\app-release.apk', (Join-Path $desktop '看影音-2.1.102.apk')),
  @('build\app\outputs\bundle\release\app-release.aab', (Join-Path $desktop '看影音-2.1.102.aab'))
)
foreach ($pair in $pairs) {
  $sourceHash = (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash
  $desktopHash = (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash
  [pscustomobject]@{
    Source = $pair[0]
    SourceHash = $sourceHash
    Desktop = $pair[1]
    DesktopHash = $desktopHash
    Match = $sourceHash -eq $desktopHash
  }
}
```

Expected: 三行 `Match=True`。记录 APK、AAB、MSIX 和异机 ZIP 的最终 SHA-256 供交付说明使用。

- [ ] **Step 4: 再次记录 Windows 已安装版本但不安装新包**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, PackageFullName
```

Expected: 已安装版本保持 Task 0 的值，因为本轮没有安装 MSIX；不要用“版本号相同”推断已安装二进制与新包一致。

- [ ] **Step 5: 检查最终 diff，只提交本轮版本与文案**

Run:

```powershell
git status --short
git diff --check
git diff -- pubspec.yaml android/app/build.gradle.kts `
  tool/android/build_signed_release.ps1 lib/core/app_version.dart `
  lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md `
  test/android_release_packaging_test.dart `
  test/release_config_contract_test.dart test/version_consistency_test.dart `
  test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git add pubspec.yaml android/app/build.gradle.kts `
  tool/android/build_signed_release.ps1 lib/core/app_version.dart `
  lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md `
  test/android_release_packaging_test.dart `
  test/release_config_contract_test.dart test/version_consistency_test.dart `
  test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --cached --check
git diff --cached --stat
git commit -m '发布：交付2.1.102测试版'
```

Expected: 提交只包含本轮 2.1.102 版本、测试与发布文案；安装包和签名秘密没有进入 Git。

- [ ] **Step 6: 确认最终仓库状态和提交链**

Run:

```powershell
git status --short
git log -7 --oneline
```

Expected: 工作区干净或只剩用户原有且已记录的无关改动；提交链依次保留设计文档、Full 依赖、包级验证、沉浸状态、彻底沉浸和 2.1.102 测试版交付。不要 push。

## Task 8: Android 实机验收与诊断闭环

**Files:**
- User artifact: desktop `看影音-2.1.102.apk`
- User output: new Android diagnostic ZIP and fullscreen screenshot

- [ ] **Step 1: 向用户交付 APK 与明确的测试顺序**

Do not install automatically. Ask the user to install the desktop APK and test in this order:

1. 播放只有 TrueHD/MLP 音轨的 MKV，确认持续有声且左右声道正常。
2. 播放本次问题 4K HEVC 文件，确认视频仍使用硬件解码，暂停、拖动、缓冲恢复正常。
3. 切换 AC3、DTS、普通立体声音轨和内嵌字幕，确认选轨没有回归。
4. 播放夸克等现有网盘视频，检查打开、跳播和退出。
5. 进入横屏，显示控制层、旋转、切后台再返回，确认底部白色导航区不再出现。
6. 从屏幕边缘滑动临时唤出系统栏，再等待其自动隐藏；退出播放器后确认系统栏和方向恢复。

- [ ] **Step 2: 要求导出新的诊断 ZIP 并按确定性标识验收**

The diagnostic summary must contain:

```text
Android 原生媒体包: full-v1.1.11
```

The player log must contain equivalent success evidence for:

```text
Selected decoder: truehd
AO: [opensles]
audio=playing
```

Accept minor log-format differences only when they still prove TrueHD/MLP decoder selection, OpenSL ES stereo output, and active audio playback. The log must not contain:

```text
Codec list:
(no decoders)
Failed to initialize a decoder for codec 'truehd'
switched from TrueHD to audio track
```

- [ ] **Step 3: 根据实机结果决定是否保留 Full override**

Expected success: TrueHD-only file has stable stereo audio, 4K HEVC remains MediaCodec hardware decoded, subtitles/cloud playback remain usable, and fullscreen stays immersive across all lifecycle cases.

Stop and do not call the fix formally complete if any of these occur: TrueHD remains silent, video hardware decoding regresses, Full v1.1.11 breaks a supported format/device, system bars cannot recover on exit, or new diagnostics lack `full-v1.1.11`. Keep the test package and diagnostic evidence; revert only the independent Full or immersive commit after identifying which subsystem failed.

## 完成定义

- 自动化：`flutter test --no-pub`、`flutter analyze --no-pub`、`:app:testDebugUnitTest` 全部通过。
- 原生资产：四个 JAR 固定哈希通过，APK/AAB 四 ABI 的 `libmpv.so` 与 Full JAR 一致。
- 交付：签名 MSIX/APK/AAB 验证通过并复制到桌面，版本分别为 `2.1.102.0`、`2.1.102 (20102)`。
- Git：只提交本轮相关文件，工作区状态清楚，没有推送。
- 实机：只有 TrueHD 音轨的文件有稳定立体声，视频硬解无回归，横屏彻底沉浸且退出恢复正常。
- 文案：在收到通过验收的新诊断日志前始终使用“测试修复，待实机验证”，不宣称正式修复。
