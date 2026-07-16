import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';

class EncodingUtils {
  static Future<String> calculateFileHash(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
