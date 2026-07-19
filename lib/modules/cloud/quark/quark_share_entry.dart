class QuarkShareEntry {
  const QuarkShareEntry({
    required this.id,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.fileToken,
  });

  final String id;
  final String name;
  final bool isDirectory;
  final int size;
  final String fileToken;

  @override
  String toString() => 'QuarkShareEntry(id: $id, name: $name)';
}

class QuarkShareInspection {
  const QuarkShareInspection({
    required this.shareId,
    required this.entries,
  });

  final String shareId;
  final List<QuarkShareEntry> entries;

  @override
  String toString() =>
      'QuarkShareInspection(shareId: $shareId, entries: ${entries.length})';
}
