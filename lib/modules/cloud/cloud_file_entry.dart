class CloudFileEntry {
  const CloudFileEntry({
    required this.id,
    required this.remotePath,
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.isDirectory,
  });

  final String id;
  final String remotePath;
  final String name;
  final int size;
  final DateTime? modifiedAt;
  final bool isDirectory;
}
