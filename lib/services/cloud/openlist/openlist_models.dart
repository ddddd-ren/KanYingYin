import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';

class OpenListFile {
  const OpenListFile({
    required this.entry,
    this.rawUrl,
    this.headers = const <String, String>{},
  });

  final CloudFileEntry entry;
  final Uri? rawUrl;
  final Map<String, String> headers;

  factory OpenListFile.fromJson(
    Map<String, dynamic> json, {
    String? remotePath,
  }) {
    final name = _string(json['name']);
    final path = remotePath ?? _string(json['path']);
    final rawUrl = _string(json['raw_url']);
    final headerValue = json['header'] ?? json['headers'];
    return OpenListFile(
      entry: CloudFileEntry(
        id: path,
        remotePath: path,
        name: name,
        size: _integer(json['size']),
        modifiedAt: DateTime.tryParse(_string(json['modified'])),
        isDirectory: json['is_dir'] == true,
      ),
      rawUrl: rawUrl.isEmpty ? null : Uri.tryParse(rawUrl),
      headers: headerValue is Map
          ? headerValue.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  static int _integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  String toString() => 'OpenListFile(${entry.remotePath}, <redacted>)';
}

class OpenListListPage {
  const OpenListListPage({required this.files, required this.total});

  final List<OpenListFile> files;
  final int total;

  factory OpenListListPage.fromJson(
    Map<String, dynamic> json, {
    required String parentPath,
  }) {
    final content = json['content'];
    if (content is! List || json['total'] is! num) {
      throw const FormatException('OpenList 列表结构不兼容');
    }
    return OpenListListPage(
      files: content.whereType<Map<Object?, Object?>>().map((item) {
        final data = Map<String, dynamic>.from(item);
        return OpenListFile.fromJson(
          data,
          remotePath: _joinPath(parentPath, _string(data['name'])),
        );
      }).toList(growable: false),
      total: (json['total'] as num).toInt(),
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  static String _joinPath(String parent, String name) {
    final segments = <String>[
      ...parent.trim().split('/').where((part) => part.isNotEmpty),
      ...name.split('/').where((part) => part.isNotEmpty),
    ];
    return '/${segments.join('/')}';
  }
}
