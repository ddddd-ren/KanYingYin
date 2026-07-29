import 'package:kanyingyin/utils/logger.dart';

/// 写入已经结构化、且不包含请求正文或凭据的网盘请求阶段信息。
void writeCloudRequestDiagnostic(String message) {
  AppLogger().i(message);
}
