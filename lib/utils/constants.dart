import 'package:flutter/material.dart';

class StyleString {
  static const double cardSpace = 10;
  static const double safeSpace = 16;
  static BorderRadius mdRadius = BorderRadius.circular(12);
  static const Radius imgRadius = Radius.circular(14);
  static const double aspectRatio = 16 / 10;
  static const Duration animationDuration = Duration(milliseconds: 280);
  static const Duration fastAnimationDuration = Duration(milliseconds: 180);
  static const Curve defaultCurve = Curves.easeOutCubic;
  static const Curve decelerateCurve = Curves.decelerate;
}

const String customAppFontFamily = "MI_Sans_Regular";

/// `year2023` flag is deprecated since 3.29 but not default to false yet. Keep
/// it to false so we have the latest M3 style process indicator.
// ignore: deprecated_member_use
const ProgressIndicatorThemeData progressIndicatorTheme2024 =
    // ignore: deprecated_member_use
    ProgressIndicatorThemeData(year2023: false);

/// `year2023` flag is deprecated since 3.29 but not default to false yet. Keep
/// it to false so we have the latest M3 style slider.
// ignore: deprecated_member_use
const SliderThemeData sliderTheme2024 = SliderThemeData(
  // ignore: deprecated_member_use
  year2023: false,
  // ignore: deprecated_member_use
  showValueIndicator: ShowValueIndicator.always,
);

/// The page transition method defined here is managed by flutter, and the native transition method of flutter is set here.
/// Transition method here will be overridden by the transition method of modular, and do not set the transition method in modular to prevent
/// the native transition method from failing
const PageTransitionsTheme pageTransitionsTheme2024 = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.linux: _SmoothFadeUpPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: _SmoothFadeUpPageTransitionsBuilder(),
  },
);

class _SmoothFadeUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SmoothFadeUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 0.03),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
        )),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Layout breakpoint according to google:
/// https://developer.android.com/develop/ui/compose/layouts/adaptive/use-window-size-classes.
///
/// **It's only a suggestion since not every device meet the breakpoint requirement.
/// You need to build layout with some more judgements.**
///
/// Some example device(portrait) width x height:
///
/// * iPhone SE3: 375 x 667
/// * iPhone 16: 393 x 852
/// * iPad Pro 11-inch: 834 x 1210
/// * HW MATE60 Pro: 387.7 x 836.9
/// * OHOS in floating window: 387.7 x 631.7 or 218.1
class LayoutBreakpoint {
  static const Map<String, double> compact = {'width': 600, 'height': 480};
  static const Map<String, double> medium = {'width': 840, 'height': 900};
}

/// 随机UA列表
const List<String> userAgentsList = [
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.1',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0',
];

/// 随机HTTP请求头accept-language字段列表
const List<String> acceptLanguageList = [
  'zh-CN,zh;q=0.9',
  'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
  'zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6',
];

/// 可选解码方式
const String defaultHardwareDecoder = 'auto';

const Map<String, String> hardwareDecodersList = {
  'auto': '自动',
  'no': 'CPU兼容',
  'auto-safe': '自动安全',
  'auto-copy': '自动拷贝',
  'd3d11va-copy': 'D3D11拷贝',
  'd3d11va': 'D3D11直通',
  'dxva2-copy': 'DXVA2拷贝',
  'dxva2': 'DXVA2直通',
};

const Map<String, String> hardwareDecoderDescriptions = {
  'auto': '由播放器自动选择可用解码方式',
  'no': '关闭硬件解码，优先保证兼容性',
  'auto-safe': '自动选择稳定的安全硬解模式',
  'auto-copy': '自动选择带拷贝的硬解模式',
  'd3d11va-copy': 'Windows 推荐，兼容性较好',
  'd3d11va': 'D3D11 直通，性能高但更挑环境',
  'dxva2-copy': '旧设备可用，兼容 Windows 7+',
  'dxva2': 'DXVA2 直通，适合旧显卡链路',
};

String normalizeHardwareDecoder(String? value) {
  if (value != null && hardwareDecodersList.containsKey(value)) {
    return value;
  }
  return defaultHardwareDecoder;
}

String hardwareDecoderLabel(String? value) {
  return hardwareDecodersList[normalizeHardwareDecoder(value)] ??
      hardwareDecodersList[defaultHardwareDecoder]!;
}

/// Android 可选视频渲染器
const Map<String, String> androidVideoRenderersList = {
  'auto': '自动选择',
  'gpu': '基于 OpenGL, 通用和稳健的选项',
  'gpu-next': '基于 Vulkan, 在新设备上表现最好',
  'mediacodec_embed': '功耗最低，不支持超分辨率',
};

/// 超分辨率滤镜
const List<String> mpvAnime4KShaders = [
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_VL.glsl',
  'Anime4K_Upscale_CNN_x2_VL.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl'
];

/// 超分辨率滤镜 (轻量)
const List<String> mpvAnime4KShadersLite = [
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_M.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_S.glsl'
];

/// 可选播放倍速
const List<double> defaultPlaySpeedList = [
  0.25,
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
  2.25,
  2.5,
  2.75,
  3.0,
];

/// 可选默认视频比例
const Map<int, String> aspectRatioTypeMap = {
  1: "自动",
  2: "裁切填充",
  3: "拉伸填充",
};

/// 可选播放器日志等级
/// LogLevel 0: 错误 1: 警告 2: 简略 3: 详细 4: 调试（隐藏） 5: 全部（隐藏）
const Map<int, String> playerLogLevelMap = {
  0: "错误",
  1: "警告",
  2: "简略",
  3: "详细",
  // 以下两个级别被MPV官方支持，但是输出内容过于冗长，暂时隐藏
  // 4: "调试",
  // 5: "全部",
};

final List<String> defaultAnimeTags = const [
  '日常',
  '原创',
  '校园',
  '搞笑',
  '奇幻',
  '百合',
  '恋爱',
  '悬疑',
  '热血',
  '后宫',
  '机战',
  '轻改',
  '偶像',
  '治愈',
  '异世界',
];

// 播放器默认快捷键
final Map<String, List<String>> defaultShortcuts = const {
  'playorpause': [' '],
  'forward': ['Arrow Right'],
  'rewind': ['Arrow Left'],
  'next': ['N'],
  'prev': ['P'],
  'volumeup': ['Arrow Up'],
  'volumedown': ['Arrow Down'],
  'togglemute': ['M'],
  'fullscreen': ['F'],
  'exitfullscreen': ['Escape'],
  'screenshot': ['S'],
  'skip': ['K'],
  'speed1': ['1'],
  'speed2': ['2'],
  'speed3': ['3'],
  'speedup': ['X'],
  'speeddown': ['Z'],
};

// 键位别名
final Map<String, String> keyAliases = {
  ' ': '空格',
  'Arrow Up': '↑',
  'Arrow Down': '↓',
  'Arrow Left': '←',
  'Arrow Right': '→',
  'Enter': '回车',
  'Tab': 'Tab',
  'Escape': 'Esc',
  'Backspace': '退格',
};

//功能中文名对应
final Map<String, String> shortcutsChineseName = {
  'playorpause': '播放 / 暂停',
  'forward': '快进 / 长按倍速',
  'rewind': '快退',
  'next': '下一集',
  'prev': '上一集',
  'volumeup': '音量加',
  'volumedown': '音量减',
  'togglemute': '静音',
  'fullscreen': '全屏',
  'exitfullscreen': '退出全屏',
  'screenshot': '截图',
  'skip': '跳过',
  'speed1': '倍速：1x',
  'speed2': '倍速：2x',
  'speed3': '倍速：3x',
  'speedup': '倍速加',
  'speeddown': '倍速减',
};
