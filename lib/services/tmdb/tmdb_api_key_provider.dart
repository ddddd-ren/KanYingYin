enum TmdbApiKeySource { none, builtin, user }

class TmdbApiKeyProvider {
  TmdbApiKeyProvider({
    required String Function() userKeyReader,
    String builtinKey = const String.fromEnvironment(
      'KANYINGYIN_TMDB_API_KEY',
    ),
  })  : _userKeyReader = userKeyReader,
        _builtinKey = builtinKey;

  final String Function() _userKeyReader;
  final String _builtinKey;

  String read() => _resolve().$1;

  TmdbApiKeySource get source => _resolve().$2;

  (String, TmdbApiKeySource) _resolve() {
    try {
      final userKey = _userKeyReader().trim();
      if (userKey.isNotEmpty) return (userKey, TmdbApiKeySource.user);
    } on Object {
      // 设置尚未初始化时继续尝试使用构建时默认值。
    }
    final builtinKey = _builtinKey.trim();
    if (builtinKey.isNotEmpty) {
      return (builtinKey, TmdbApiKeySource.builtin);
    }
    return ('', TmdbApiKeySource.none);
  }
}
