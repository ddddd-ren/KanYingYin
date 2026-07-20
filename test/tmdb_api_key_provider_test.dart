import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';

void main() {
  test('用户 TMDB Key 优先于内置默认值', () {
    final provider = TmdbApiKeyProvider(
      userKeyReader: () => ' user-key ',
      builtinKey: 'builtin-key',
    );

    expect(provider.read(), 'user-key');
    expect(provider.source, TmdbApiKeySource.user);
  });

  test('用户 Key 为空时使用内置默认值', () {
    final provider = TmdbApiKeyProvider(
      userKeyReader: () => '  ',
      builtinKey: ' builtin-key ',
    );

    expect(provider.read(), 'builtin-key');
    expect(provider.source, TmdbApiKeySource.builtin);
  });

  test('用户 Key 读取失败且无内置值时返回无凭据', () {
    final provider = TmdbApiKeyProvider(
      userKeyReader: () => throw StateError('setting unavailable'),
      builtinKey: '',
    );

    expect(provider.read(), isEmpty);
    expect(provider.source, TmdbApiKeySource.none);
  });
}
