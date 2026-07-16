import 'package:path/path.dart' as p;

class LocalVideoFileTypes {
  const LocalVideoFileTypes._();

  static const int minRecognizedVideoSizeBytes = 800 * 1024 * 1024;

  static const Set<String> videoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.wmv',
    '.flv',
    '.webm',
    '.m4v',
    '.mpg',
    '.mpeg',
    '.ts',
    '.m2ts',
    '.rmvb',
    '.rm',
    '.3gp',
    '.3g2',
    '.ogv',
    '.vob',
    '.asf',
    '.divx',
    '.hevc',
  };

  static const Set<String> windowsSystemDirectoryNames = {
    'system volume information',
    r'$recycle.bin',
    'recovery',
  };

  static bool isWindowsSystemDirectory(String name) =>
      windowsSystemDirectoryNames.contains(name.toLowerCase());

  static bool isVideoPath(String path) {
    return videoExtensions.contains(p.extension(path).toLowerCase());
  }

  static bool isRecognizedVideo(
    String path, {
    required int size,
    int minSizeBytes = minRecognizedVideoSizeBytes,
  }) {
    return isVideoPath(path) &&
        isRecognizedVideoSize(
          size,
          minSizeBytes: minSizeBytes,
        );
  }

  static bool isRecognizedVideoSize(
    int size, {
    int minSizeBytes = minRecognizedVideoSizeBytes,
  }) {
    return size > 0 && size > minSizeBytes;
  }
}
