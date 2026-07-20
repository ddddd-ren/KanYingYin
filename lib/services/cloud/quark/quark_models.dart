class QuarkAccount {
  const QuarkAccount({required this.nickname});
  final String nickname;
}

class QuarkFile {
  const QuarkFile({
    required this.id,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
    required this.category,
    this.shareFileToken,
  });

  final String id;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modifiedAt;
  final int category;
  final String? shareFileToken;
}

class QuarkDirectoryPage {
  const QuarkDirectoryPage({
    required this.items,
    required this.page,
    required this.size,
    required this.total,
  });

  final List<QuarkFile> items;
  final int page;
  final int size;
  final int total;
}

enum QuarkPlaybackLinkType { transcode, originalDownload }

class QuarkNoTranscodingLinkException implements Exception {
  const QuarkNoTranscodingLinkException();
}

class QuarkPlaybackLink {
  const QuarkPlaybackLink({
    required this.fileId,
    required this.uri,
    this.type = QuarkPlaybackLinkType.transcode,
  });

  final String fileId;
  final Uri uri;
  final QuarkPlaybackLinkType type;
}
