abstract final class BaiduEndpoints {
  static final Uri account = Uri.https('pan.baidu.com', '/rest/2.0/xpan/nas');
  static final Uri file = Uri.https('pan.baidu.com', '/rest/2.0/xpan/file');
  static final Uri multimedia =
      Uri.https('pan.baidu.com', '/rest/2.0/xpan/multimedia');
}

class BaiduRequestPolicy {
  const BaiduRequestPolicy();

  bool isOfficialApiUri(Uri uri) =>
      uri.scheme == 'https' && uri.host == 'pan.baidu.com';
}
