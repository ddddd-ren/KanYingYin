# Flutter 引擎与插件注册入口由清单或反射加载。
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# 后台音频服务和媒体按钮接收器由 Android 系统实例化。
-keep class com.ryanheise.audioservice.** { *; }

# WebView 平台实现包含 JavaScript bridge 与反射调用。
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# media_kit 原生播放器通过 JNI 和插件注册加载。
-keep class com.alexmercerind.media_kit_libs_android_video.** { *; }
-keep class com.alexmercerind.mediakit.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# 项目未使用 Flutter 延迟组件，忽略其对可选 Play Core API 的静态引用。
-dontwarn com.google.android.play.core.**
