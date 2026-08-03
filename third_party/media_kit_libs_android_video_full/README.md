# media_kit_libs_android_video Full 适配包

本目录只覆盖看影音的 Android 原生媒体依赖。插件接口来自项目固定的
Predidit/media-kit 提交 `21aacaf9600c4bd00f2a3c57310363bc0cc9597f`，原生 JAR 固定为
media-kit/libmpv-android-video-build `v1.1.11` 的四个 Full 资产。

每个 JAR 在 Gradle 下载阶段校验 SHA-256。Android 发布脚本还会比较 JAR、APK 和
AAB 内各 ABI 的 `libmpv.so`。删除根 `pubspec.yaml` 中的 override 即可恢复传递依赖。
