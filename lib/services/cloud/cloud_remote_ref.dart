class CloudRemoteRef {
  const CloudRemoteRef({required this.id, required this.path});

  final String id;
  final String path;

  factory CloudRemoteRef.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final path = json['path'];
    if (id is! String || path is! String) {
      throw const FormatException('网盘远程引用结构不兼容');
    }
    return CloudRemoteRef(id: id, path: path);
  }

  Map<String, String> toJson() => <String, String>{'id': id, 'path': path};

  @override
  bool operator ==(Object other) =>
      other is CloudRemoteRef && other.id == id && other.path == path;

  @override
  int get hashCode => Object.hash(id, path);

  @override
  String toString() => 'CloudRemoteRef(id: $id, path: $path)';
}
