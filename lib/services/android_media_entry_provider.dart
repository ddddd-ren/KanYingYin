import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/platform/android/android_document_provider.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';

class AndroidMediaEntryProvider implements LocalMediaEntryProvider {
  const AndroidMediaEntryProvider(this._documents);

  final AndroidDocumentProvider _documents;

  @override
  bool supports(MediaLocation location) => location.isDocument;

  @override
  Future<bool> canAccess(MediaLocation location) {
    if (!supports(location)) return Future<bool>.value(false);
    return _documents.canAccess(location);
  }

  @override
  Future<List<LocalMediaEntry>> listChildren(
    MediaLocation directory,
  ) async {
    if (!supports(directory)) {
      throw const AndroidDocumentException('InvalidInput');
    }
    final entries = await _documents.listChildren(directory);
    return entries
        .map(
          (entry) => LocalMediaEntry(
            location: entry.location,
            name: entry.name,
            isDirectory: entry.isDirectory,
            size: entry.size,
            modified: entry.modified,
            mimeType: entry.mimeType,
          ),
        )
        .toList(growable: false);
  }
}
