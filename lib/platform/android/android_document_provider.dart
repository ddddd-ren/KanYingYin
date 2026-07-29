import 'package:flutter/services.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/platform/android/android_platform_channel.dart';

class AndroidDocumentException implements Exception {
  const AndroidDocumentException(this.code);

  final String code;

  @override
  String toString() => 'AndroidDocumentException($code)';
}

class AndroidDocumentEntry {
  const AndroidDocumentEntry({
    required this.location,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.mimeType,
  });

  final MediaLocation location;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String mimeType;
}

abstract interface class AndroidDocumentProvider {
  Future<({MediaLocation location, String name})?> pickDirectory();

  Future<bool> canAccess(MediaLocation location);

  Future<List<AndroidDocumentEntry>> listChildren(MediaLocation parent);

  Future<Uint8List> readSmallFile(
    MediaLocation location, {
    required int maxBytes,
  });
}

class MethodChannelAndroidDocumentProvider implements AndroidDocumentProvider {
  const MethodChannelAndroidDocumentProvider(this._channel);

  final AndroidPlatformChannel _channel;

  @override
  Future<({MediaLocation location, String name})?> pickDirectory() {
    return _guard(() async {
      final raw = await _channel.pickDocumentDirectory();
      if (raw == null) return null;
      return (
        location: MediaLocation.document(
          uri: _string(raw, 'documentUri'),
          treeUri: _string(raw, 'treeUri'),
        ),
        name: _string(raw, 'name'),
      );
    });
  }

  @override
  Future<bool> canAccess(MediaLocation location) {
    _requireDocument(location);
    return _guard(
      () => _channel.canAccessDocument(location.value, location.treeUri!),
    );
  }

  @override
  Future<List<AndroidDocumentEntry>> listChildren(
    MediaLocation parent,
  ) {
    _requireDocument(parent);
    return _guard(() async {
      final raw = await _channel.listDocumentChildren(
        parent.value,
        parent.treeUri!,
      );
      return raw.map((item) {
        final mimeType = _string(item, 'mimeType');
        return AndroidDocumentEntry(
          location: MediaLocation.document(
            uri: _string(item, 'documentUri'),
            treeUri: parent.treeUri!,
          ),
          name: _string(item, 'name'),
          isDirectory: mimeType == 'vnd.android.document/directory',
          size: _int(item, 'size'),
          modified: DateTime.fromMillisecondsSinceEpoch(
            _int(item, 'modified'),
          ),
          mimeType: mimeType,
        );
      }).toList(growable: false);
    });
  }

  @override
  Future<Uint8List> readSmallFile(
    MediaLocation location, {
    required int maxBytes,
  }) {
    _requireDocument(location);
    if (maxBytes <= 0) {
      throw const AndroidDocumentException('InvalidInput');
    }
    return _guard(
      () => _channel.readSmallDocument(location.value, maxBytes),
    );
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      throw AndroidDocumentException(error.code);
    } on FormatException {
      throw const AndroidDocumentException('InvalidResponse');
    }
  }

  static void _requireDocument(MediaLocation location) {
    if (!location.isDocument || location.treeUri == null) {
      throw const AndroidDocumentException('InvalidInput');
    }
  }

  static String _string(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Android 文档响应缺少 $key');
  }

  static int _int(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
