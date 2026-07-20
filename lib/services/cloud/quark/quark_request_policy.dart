class QuarkRequestPolicy {
  const QuarkRequestPolicy();

  static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'quark-cloud-drive/3.14.2 Chrome/112.0.5615.165 '
      'Electron/24.1.3.8 Safari/537.36 Channel/pckk_other_ch';

  static const Set<String> apiHosts = <String>{
    'pan.quark.cn',
    'drive.quark.cn',
    'drive-pc.quark.cn',
  };

  Map<String, String> headersFor(
    Uri uri, {
    required String cookie,
    Uri? playbackOrigin,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'Referer': 'https://pan.quark.cn',
      'User-Agent': userAgent,
    };
    if (_mayAttachCookie(uri, playbackOrigin: playbackOrigin)) {
      headers['Cookie'] = cookie;
    }
    return Map<String, String>.unmodifiable(headers);
  }

  Map<String, String> headersForRedirect({
    required Uri from,
    required Uri to,
    required Map<String, String> headers,
  }) {
    final redirected = Map<String, String>.from(headers);
    if (from.scheme.toLowerCase() != 'https' ||
        to.scheme.toLowerCase() != 'https' ||
        from.host.toLowerCase() != to.host.toLowerCase()) {
      redirected.remove('Cookie');
    }
    return Map<String, String>.unmodifiable(redirected);
  }

  bool isTrustedOriginalDownloadUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'drive.quark.cn' ||
        host.endsWith('.drive.quark.cn') ||
        host == 'pds.quark.cn' ||
        host.endsWith('.pds.quark.cn');
  }

  Map<String, String> originalDownloadHeadersFor(
    Uri uri, {
    required String cookie,
  }) {
    if (!isTrustedOriginalDownloadUri(uri)) {
      return const <String, String>{};
    }
    return Map<String, String>.unmodifiable(<String, String>{
      'Cookie': cookie,
      'Referer': 'https://pan.quark.cn',
      'User-Agent': userAgent,
    });
  }

  bool shouldRetry({required int statusCode, required int attempt}) =>
      attempt < 2 &&
      statusCode != 401 &&
      statusCode != 403 &&
      (statusCode == 429 || statusCode >= 500);

  Duration retryDelay(int attempt) =>
      Duration(milliseconds: 500 * (1 << attempt.clamp(0, 2)));

  bool _mayAttachCookie(Uri uri, {required Uri? playbackOrigin}) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    if (apiHosts.contains(host)) return true;
    return playbackOrigin != null &&
        playbackOrigin.scheme.toLowerCase() == 'https' &&
        playbackOrigin.host.toLowerCase() == host;
  }
}
