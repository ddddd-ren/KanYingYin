class BaiduOAuthTokens {
  BaiduOAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required Set<String> scopes,
  }) : scopes = Set<String>.unmodifiable(scopes);

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final Set<String> scopes;
}
