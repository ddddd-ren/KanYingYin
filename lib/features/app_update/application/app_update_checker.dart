import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';

typedef LatestReleaseFetcher = Future<AppRelease> Function();
typedef UpdateClock = DateTime Function();

class AppUpdateChecker {
  const AppUpdateChecker({
    required this.localVersion,
    required LatestReleaseFetcher fetchLatestRelease,
  }) : _fetchLatestRelease = fetchLatestRelease;

  final SemanticVersion localVersion;
  final LatestReleaseFetcher _fetchLatestRelease;

  Future<AppUpdateCheckResult> check() async {
    final release = await _fetchLatestRelease();
    final order = release.version.compareTo(localVersion);
    if (order > 0) return AppUpdateCheckResult.updateAvailable(release);
    if (order < 0) return const AppUpdateCheckResult.localAhead();
    return const AppUpdateCheckResult.upToDate();
  }
}

class DailyUpdateCheckPolicy {
  DailyUpdateCheckPolicy({required this.settings, UpdateClock? now})
      : _now = now ?? DateTime.now;

  final TypedSettings settings;
  final UpdateClock _now;

  bool get isDue =>
      settings.getTyped<String>(
        SettingBoxKey.lastSuccessfulUpdateCheckDate,
        defaultValue: '',
      ) !=
      _today;

  Future<void> markSuccessful() => settings.put(
        SettingBoxKey.lastSuccessfulUpdateCheckDate,
        _today,
      );

  String get _today {
    final value = _now().toLocal();
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}
