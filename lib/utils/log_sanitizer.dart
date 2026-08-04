class LogSanitizer {
  const LogSanitizer();

  static final RegExp _remoteUrlPattern = RegExp(
    r'''(?:https?|ftp|rtsp|rtmp)://[^\s<>\[\]{}()"']+''',
    caseSensitive: false,
  );

  static final List<RegExp> _headerPatterns = [
    RegExp(
      r'^([^\{,\r\n]*\bauthorization\s*:\s*)(?:digest|aws4-[^\s,]+)\b[^\r\n]*',
      caseSensitive: false,
      multiLine: true,
    ),
    RegExp(
      r'\b(authorization\s*:\s*)(?:\[REDACTED\]|[^\s,;&}\]\r\n]+)(?:[ \t]+(?![^\s,:=;&{}\[\]]+\s*[:=])(?:\[REDACTED\]|[^\s,;&}\]\r\n]+))*',
      caseSensitive: false,
    ),
    // Cookie 请求头可能带日志前缀；Map 和 JSON 则交给字段规则按边界处理。
    RegExp(
      r'^([^\{\r\n]*\bcookie\s*:\s*)[^\r\n]*',
      caseSensitive: false,
      multiLine: true,
    ),
  ];

  static final RegExp _keyValuePattern = RegExp(
    r'''\b((?:access[_-]?token|refresh[_-]?token|captcha[_-]?token|credit[_-]?key|creditkey|token|api[_-]?key|client[_-]?secret|cookie|authorization|signature|password|passwd|secret)\s*[:=]\s*)(?:"(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|(?:\[REDACTED\]|[^\s,;&}\]\r\n]+)(?:[ \t]+(?![^\s,:=;&{}\[\]]+\s*[:=])(?:\[REDACTED\]|[^\s,;&}\]\r\n]+))*)''',
    caseSensitive: false,
  );

  static final RegExp _exportStructuredCookiePattern = RegExp(
    r'''(["']?\bcookie\b["']?\s*:\s*)(?:"(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|\[REDACTED\][^,}\]\r\n]*|[^,}\]\r\n]+)''',
    caseSensitive: false,
  );

  static final RegExp _exportStructuredAuthorizationPattern = RegExp(
    r'''(["']?\bauthorization\b["']?\s*:\s*)(?:"(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|\[REDACTED\][^}\]\r\n]*?|[^}\]\r\n]*?)(?=,\s*[^,\s:=;&{}\[\]]+\s*:|[}\]\r\n]|$)''',
    caseSensitive: false,
  );

  static final RegExp _exportCredentialPattern = RegExp(
    r'''(["']?\b(?:access[_-]?token|refresh[_-]?token|captcha[_-]?token|credit[_-]?key|creditkey|token|api[_-]?key|client[_-]?secret|cookie|authorization|signature|password|passwd|secret)\b["']?\s*[:=]\s*)(?:"(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|(?:\[REDACTED\]|[^\s,;&}\]\r\n]+)(?:[ \t]+(?![^\s,:=;&{}\[\]]+\s*[:=])(?:\[REDACTED\]|[^\s,;&}\]\r\n]+))*)''',
    caseSensitive: false,
  );

  static final RegExp _quotedLocalPathPattern = RegExp(
    r'''(?:"(?:[a-z]:[\\/]|\\\\|/(?:users|home)/)[^"\r\n]*"|'(?:[a-z]:[\\/]|\\\\|/(?:users|home)/)[^'\r\n]*')''',
    caseSensitive: false,
  );

  static final RegExp _localPathPattern = RegExp(
    r'''(^|[^a-z0-9])(?:[a-z]:[\\/]|\\\\|/(?:users|home)/)[^"\r\n]*''',
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
      _exportStructuredCookiePattern,
      (match) => '${match.group(1)}[REDACTED]',
    );
    result = result.replaceAllMapped(
      _exportStructuredAuthorizationPattern,
      (match) => '${match.group(1)}[REDACTED]',
    );
    result = result.replaceAllMapped(
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
