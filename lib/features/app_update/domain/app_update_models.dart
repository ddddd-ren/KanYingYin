final class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  factory SemanticVersion.parse(String source) => _parse(source, tagged: false);

  factory SemanticVersion.parseTag(String source) =>
      _parse(source, tagged: true);

  final int major;
  final int minor;
  final int patch;

  static SemanticVersion _parse(String source, {required bool tagged}) {
    final pattern = tagged
        ? RegExp(r'^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
        : RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$');
    final match = pattern.firstMatch(source);
    if (match == null) throw FormatException('版本格式无效: $source');
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final minorOrder = minor.compareTo(other.minor);
    return minorOrder != 0 ? minorOrder : patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is SemanticVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

final class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.size,
    required this.sha256,
    required this.downloadUri,
  });

  final String name;
  final int size;
  final String sha256;
  final Uri downloadUri;
}

final class AppRelease {
  const AppRelease({
    required this.version,
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.assets,
  });

  final SemanticVersion version;
  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final List<AppReleaseAsset> assets;

  AppReleaseAsset get windowsInstaller {
    final versionText = version.toString();
    final candidates = assets
        .where(
          (asset) =>
              asset.name.toLowerCase().endsWith('.exe') &&
              asset.name.contains(versionText),
        )
        .toList(growable: false);
    if (candidates.length != 1) {
      throw StateError('正式版必须恰好包含一个版本匹配的 Windows EXE');
    }
    return candidates.single;
  }
}

enum AppUpdateCheckStatus { updateAvailable, upToDate, localAhead }

final class AppUpdateCheckResult {
  const AppUpdateCheckResult._(this.status, this.release);

  const AppUpdateCheckResult.updateAvailable(AppRelease release)
      : this._(AppUpdateCheckStatus.updateAvailable, release);

  const AppUpdateCheckResult.upToDate()
      : this._(AppUpdateCheckStatus.upToDate, null);

  const AppUpdateCheckResult.localAhead()
      : this._(AppUpdateCheckStatus.localAhead, null);

  final AppUpdateCheckStatus status;
  final AppRelease? release;
}
