import 'dart:io';

class MediaUriUtils {
  MediaUriUtils._();

  static String toPlayableUri(String value, {required bool isLocalPlayback}) {
    if (!isLocalPlayback || value.isEmpty || _hasSupportedUriScheme(value)) {
      return value;
    }
    return File(value).uri.toString();
  }

  static bool _hasSupportedUriScheme(String value) {
    final uri = Uri.tryParse(value);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    return switch (scheme) {
      'http' || 'https' || 'file' || 'content' || 'asset' || 'data' => true,
      _ => false,
    };
  }
}
