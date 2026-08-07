import 'package:kanyingyin/platform/android/android_platform_channel.dart';

Future<String?> pickTvImportFile({
  required String title,
  required List<String> allowedExtensions,
  required int maxBytes,
}) async {
  final selected = await const AndroidPlatformChannel().pickFile(
    title: title,
    allowedExtensions: allowedExtensions,
    maxBytes: maxBytes,
  );
  return selected?.path;
}
