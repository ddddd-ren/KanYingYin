import 'package:kanyingyin/modules/local/media_location.dart';

class LocalMediaEntry {
  const LocalMediaEntry({
    required this.location,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modified,
    this.mimeType,
  });

  final MediaLocation location;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String? mimeType;
}

abstract interface class LocalMediaEntryProvider {
  bool supports(MediaLocation location);

  Future<bool> canAccess(MediaLocation location);

  Future<List<LocalMediaEntry>> listChildren(MediaLocation directory);
}
