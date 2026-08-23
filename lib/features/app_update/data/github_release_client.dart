import 'package:dio/dio.dart';
import 'package:kanyingyin/core/network/dio_factory.dart';
import 'package:kanyingyin/core/network/network_config.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';

class GitHubReleaseClient {
  GitHubReleaseClient({Dio? dio}) : _dio = dio ?? _createDio();

  static final Uri releasesUri = Uri.parse(
    'https://api.github.com/repos/ddddd-ren/KanYingYin/releases?per_page=30',
  );

  final Dio _dio;

  Future<AppRelease> fetchLatestStableRelease() async {
    final response = await _dio.getUri<Object?>(releasesUri);
    final data = response.data;
    if (data is! List<Object?>) {
      throw const FormatException('GitHub Releases 响应不是列表');
    }

    final candidates = <_ReleaseCandidate>[];
    for (final entry in data) {
      if (entry is! Map<String, Object?> ||
          entry['draft'] != false ||
          entry['prerelease'] != false) {
        continue;
      }
      final tagName = entry['tag_name'];
      if (tagName is! String) continue;
      try {
        candidates.add(
          _ReleaseCandidate(
            version: SemanticVersion.parseTag(tagName),
            json: entry,
          ),
        );
      } on FormatException {
        continue;
      }
    }
    if (candidates.isEmpty) {
      throw const FormatException('GitHub 中没有有效正式版本');
    }
    candidates.sort((left, right) => right.version.compareTo(left.version));
    return _parseRelease(candidates.first);
  }

  static AppRelease _parseRelease(_ReleaseCandidate candidate) {
    final json = candidate.json;
    final tagName = json['tag_name'];
    final publishedAtText = json['published_at'];
    final rawAssets = json['assets'];
    if (tagName is! String ||
        publishedAtText is! String ||
        rawAssets is! List<Object?>) {
      throw const FormatException('GitHub 正式版本字段不完整');
    }
    final publishedAt = DateTime.tryParse(publishedAtText);
    if (publishedAt == null) {
      throw const FormatException('GitHub 正式版本发布时间无效');
    }

    final versionText = candidate.version.toString();
    final assets = <AppReleaseAsset>[];
    for (final value in rawAssets) {
      if (value is! Map<String, Object?>) continue;
      final name = value['name'];
      if (name is! String ||
          !name.toLowerCase().endsWith('.exe') ||
          !name.contains(versionText)) {
        continue;
      }
      assets.add(_parseWindowsAsset(value));
    }

    final release = AppRelease(
      version: candidate.version,
      tagName: tagName,
      name: json['name'] is String ? json['name']! as String : tagName,
      body: json['body'] is String ? json['body']! as String : '',
      publishedAt: publishedAt,
      assets: List<AppReleaseAsset>.unmodifiable(assets),
    );
    release.windowsInstaller;
    return release;
  }

  static AppReleaseAsset _parseWindowsAsset(Map<String, Object?> json) {
    final name = json['name'];
    final size = json['size'];
    final digest = json['digest'];
    final downloadUrl = json['browser_download_url'];
    if (name is! String ||
        size is! int ||
        size <= 0 ||
        digest is! String ||
        downloadUrl is! String) {
      throw const FormatException('GitHub Windows 安装包字段不完整');
    }
    final digestMatch = RegExp(
      r'^sha256:([0-9a-fA-F]{64})$',
    ).firstMatch(digest);
    final downloadUri = Uri.tryParse(downloadUrl);
    if (digestMatch == null ||
        downloadUri == null ||
        downloadUri.scheme != 'https') {
      throw const FormatException('GitHub Windows 安装包校验信息无效');
    }
    return AppReleaseAsset(
      name: name,
      size: size,
      sha256: digestMatch.group(1)!.toLowerCase(),
      downloadUri: downloadUri,
    );
  }

  static Dio _createDio() => DioFactory.createForConfig(
        const NetworkConfig(
          connectTimeout: Duration(seconds: 12),
          receiveTimeout: Duration(seconds: 20),
        ),
        defaultHeaders: const <String, Object?>{
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'KanYingYin-App-Updater',
        },
      );
}

final class _ReleaseCandidate {
  const _ReleaseCandidate({required this.version, required this.json});

  final SemanticVersion version;
  final Map<String, Object?> json;
}
