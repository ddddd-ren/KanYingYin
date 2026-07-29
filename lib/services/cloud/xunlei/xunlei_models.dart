class XunleiSession {
  const XunleiSession({
    required this.tokenType,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
  });

  final String tokenType;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;

  String get authorization => '$tokenType $accessToken';

  @override
  String toString() => 'XunleiSession(<redacted>)';
}

class XunleiAccount {
  const XunleiAccount({
    required this.userId,
    required this.accountLabel,
  });

  final String userId;
  final String accountLabel;
}

class XunleiFile {
  const XunleiFile({
    required this.id,
    required this.parentId,
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.isDirectory,
  });

  final String id;
  final String parentId;
  final String name;
  final int size;
  final DateTime? modifiedAt;
  final bool isDirectory;
}

class XunleiDirectoryPage {
  const XunleiDirectoryPage({
    required this.files,
    this.nextPageToken,
  });

  final List<XunleiFile> files;
  final String? nextPageToken;
}

class XunleiFileDetail {
  const XunleiFileDetail({
    required this.file,
    required this.originalUri,
    required this.transcodeUris,
  });

  final XunleiFile file;
  final Uri originalUri;
  final List<Uri> transcodeUris;
}

class XunleiVerificationRequired implements Exception {
  const XunleiVerificationRequired({
    required this.uri,
    required this.creditKey,
  });

  final Uri uri;
  final String creditKey;

  @override
  String toString() => 'XunleiVerificationRequired(<redacted>)';
}

class XunleiVerificationChallenge {
  const XunleiVerificationChallenge({
    required this.reviewUri,
    required this.creditKey,
    required this.deviceId,
    required this.deviceSign,
    required this.startedAt,
  });

  final Uri reviewUri;
  final String creditKey;
  final String deviceId;
  final String deviceSign;
  final DateTime startedAt;

  @override
  String toString() => 'XunleiVerificationChallenge(<redacted>)';
}
