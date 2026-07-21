import 'dart:io';

abstract final class BaiduEndpoints {
  static final Uri account = Uri.https('pan.baidu.com', '/rest/2.0/xpan/nas');
  static final Uri file = Uri.https('pan.baidu.com', '/rest/2.0/xpan/file');
  static final Uri multimedia =
      Uri.https('pan.baidu.com', '/rest/2.0/xpan/multimedia');
}

class BaiduRequestPolicy {
  const BaiduRequestPolicy();

  static const String downloadUserAgent = 'pan.baidu.com';

  static const Set<String> _officialDownloadHosts = <String>{
    'pan.baidu.com',
    'd.pcs.baidu.com',
    'pcs.baidu.com',
  };

  bool isOfficialApiUri(Uri uri) =>
      uri.scheme == 'https' && uri.host == 'pan.baidu.com';

  bool isOfficialDownloadUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (uri.port == 443 || !uri.hasPort) &&
      _officialDownloadHosts.contains(uri.host.toLowerCase());

  bool isSafeDownloadRedirectUri(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.host.isEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost')) return false;
    final address = InternetAddress.tryParse(host);
    if (address == null) return true;
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return false;
    }
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return !_isPrivateIpv4(bytes);
    }
    if (bytes.every((byte) => byte == 0)) return false;
    final uniqueLocal = (bytes[0] & 0xfe) == 0xfc;
    final linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80;
    return !uniqueLocal && !linkLocal;
  }

  bool _isPrivateIpv4(List<int> bytes) {
    if (bytes.length != 4) return true;
    if (bytes[0] == 0 || bytes[0] == 10 || bytes[0] == 127) return true;
    if (bytes[0] == 169 && bytes[1] == 254) return true;
    if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) return true;
    if (bytes[0] == 192 && bytes[1] == 168) return true;
    return false;
  }
}
