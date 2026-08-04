class LogSanitizer {
  const LogSanitizer();

  static final RegExp _remoteUrlPattern = RegExp(
    r'''(?:https?|ftp|rtsp|rtmp)://[^\s<>\[\]{}()"']+''',
    caseSensitive: false,
  );

  static final List<RegExp> _headerPatterns = [
    RegExp(
      r'\b(authorization\s*:\s*)(?:bearer\s+)?[^\s,;]+',
      caseSensitive: false,
    ),
    // Cookie 值允许分号和空格，必须整行清除，避免只隐藏第一个键值对。
    RegExp(r'\b(cookie\s*:\s*)[^\r\n]*', caseSensitive: false),
  ];

  static final RegExp _keyValuePattern = RegExp(
    r'\b((?:access[_-]?token|refresh[_-]?token|captcha[_-]?token|credit[_-]?key|creditkey|token|api[_-]?key|signature|password|passwd|secret)\s*[:=]\s*)[^\s,;&]+',
    caseSensitive: false,
  );

  static final RegExp _exportCredentialPattern = RegExp(
    r'''(["']?\b(?:access[_-]?token|refresh[_-]?token|captcha[_-]?token|credit[_-]?key|creditkey|token|api[_-]?key|client[_-]?secret|cookie|authorization|signature|password|passwd|secret)\b["']?\s*[:=]\s*)(?!\[REDACTED\])(?:"(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|[^\s,;&}\]\r\n]+)''',
    caseSensitive: false,
  );

  static final RegExp _quotedLocalPathPattern = RegExp(
    r'''["'](?:[a-z]:[\\/]|\\\\|/(?:users|home)/)[^"'\r\n]*["']''',
    caseSensitive: false,
  );

  static final RegExp _localPathPattern = RegExp(
    r'''(^|[^a-z0-9])(?:[a-z]:[\\/]|\\\\|/(?:users|home)/)[^"'\r\n]*''',
    caseSensitive: false,
    multiLine: true,
  );

  String sanitize(String input) {
    var result = input.replaceAllMapped(_remoteUrlPattern, (match) {
      final uri = Uri.tryParse(match.group(0)!);
      if (uri == null || uri.host.isEmpty) return '远程资源';
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$port';
    });

    for (final pattern in _headerPatterns) {
      result = result.replaceAllMapped(
        pattern,
        (match) => '${match.group(1)}[REDACTED]',
      );
    }
    return result.replaceAllMapped(
      _keyValuePattern,
      (match) => '${match.group(1)}[REDACTED]',
    );
  }

  String sanitizeForExport(String input) {
    var result = sanitize(input).replaceAllMapped(
      _exportCredentialPattern,
      (match) => '${match.group(1)}[REDACTED]',
    );
    result = result.replaceAll(_quotedLocalPathPattern, '[LOCAL_PATH]');
    return result.replaceAllMapped(
      _localPathPattern,
      (match) => '${match.group(1)}[LOCAL_PATH]',
    );
  }
}
