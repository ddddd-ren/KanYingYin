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

class BaiduAccount {
  const BaiduAccount({
    required this.displayName,
    required this.userId,
    required this.vipType,
  });

  final String displayName;
  final String userId;
  final int vipType;
}

class BaiduFileEntry {
  const BaiduFileEntry({
    required this.fsId,
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.isDirectory,
  });

  final String fsId;
  final String path;
  final String name;
  final int size;
  final DateTime modifiedAt;
  final bool isDirectory;
}

class BaiduDirectoryPage {
  BaiduDirectoryPage(List<BaiduFileEntry> entries)
      : entries = List<BaiduFileEntry>.unmodifiable(entries);

  final List<BaiduFileEntry> entries;
}

class BaiduFileDetails extends BaiduFileEntry {
  const BaiduFileDetails({
    required super.fsId,
    required super.path,
    required super.name,
    required super.size,
    required super.modifiedAt,
    required super.isDirectory,
    this.downloadUri,
  });

  final Uri? downloadUri;
}
