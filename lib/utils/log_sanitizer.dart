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
    RegExp(
      r'\b(cookie\s*:\s*)[^\s,]+',
      caseSensitive: false,
    ),
  ];

  static final RegExp _keyValuePattern = RegExp(
    r'\b((?:access[_-]?token|refresh[_-]?token|token|api[_-]?key|signature|password|passwd|secret)\s*[:=]\s*)[^\s,;&]+',
    caseSensitive: false,
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
}
