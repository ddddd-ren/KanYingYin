import 'package:path/path.dart' as p;

enum MediaLocationKind { file, document }

class MediaLocation {
  const MediaLocation._({
    required this.kind,
    required this.value,
    this.treeUri,
  });

  factory MediaLocation.file(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('文件路径不能为空');
    }
    final value = p.normalize(trimmed);
    return MediaLocation._(kind: MediaLocationKind.file, value: value);
  }

  factory MediaLocation.document({
    required String uri,
    required String treeUri,
  }) {
    final document = Uri.tryParse(uri.trim());
    final tree = Uri.tryParse(treeUri.trim());
    if (document?.scheme != 'content' || tree?.scheme != 'content') {
      throw const FormatException('Android 文档位置必须使用 content URI');
    }
    return MediaLocation._(
      kind: MediaLocationKind.document,
      value: document.toString(),
      treeUri: tree.toString(),
    );
  }

  factory MediaLocation.fromJson(Map<Object?, Object?> json) {
    final kind = json['kind']?.toString();
    final value = json['value']?.toString() ?? '';
    return switch (kind) {
      'document' => MediaLocation.document(
          uri: value,
          treeUri: json['treeUri']?.toString() ?? '',
        ),
      'file' => MediaLocation.file(value),
      _ => throw FormatException('未知媒体位置类型: $kind'),
    };
  }

  final MediaLocationKind kind;
  final String value;
  final String? treeUri;

  String get stableId => kind == MediaLocationKind.file
      ? 'file:${p.normalize(value).toLowerCase()}'
      : 'document:$value';
  bool get isFile => kind == MediaLocationKind.file;
  bool get isDocument => kind == MediaLocationKind.document;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'value': value,
        if (treeUri != null) 'treeUri': treeUri,
      };

  @override
  bool operator ==(Object other) =>
      other is MediaLocation && other.stableId == stableId;

  @override
  int get hashCode => stableId.hashCode;

  @override
  String toString() => value;
}
