import 'package:kanyingyin/platform/app_platform.dart';

abstract final class AndroidMediaBundle {
  static const String diagnosticLabel = 'full-v1.1.11';
  static const String diagnosticLine = 'Android 原生媒体包: $diagnosticLabel';

  static List<String> diagnosticLines(AppPlatformCapabilities platform) {
    if (!platform.isAndroid) return const <String>[];
    return const <String>[diagnosticLine];
  }
}
