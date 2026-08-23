import 'package:kanyingyin/features/app_update/application/app_update_checker.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';
import 'package:kanyingyin/platform/app_platform.dart';

typedef UpdateReleasePresenter = Future<void> Function(AppRelease release);
typedef UpdateMessagePresenter = void Function(String message);
typedef UpdateErrorLogger = void Function(Object error, StackTrace stackTrace);

class AppUpdateFlow {
  AppUpdateFlow({
    required AppPlatformCapabilities capabilities,
    required AppUpdateChecker checker,
    required DailyUpdateCheckPolicy policy,
    required UpdateReleasePresenter showRelease,
    required UpdateMessagePresenter showToast,
    required UpdateErrorLogger logError,
  })  : _checker = checker,
        _policy = policy,
        _showRelease = showRelease,
        _showToast = showToast,
        _logError = logError;

  final AppUpdateChecker _checker;
  final DailyUpdateCheckPolicy _policy;
  final UpdateReleasePresenter _showRelease;
  final UpdateMessagePresenter _showToast;
  final UpdateErrorLogger _logError;

  Future<void> runAutomatic() async {
    if (!_policy.isDue) return;
    try {
      final result = await _checker.check();
      await _policy.markSuccessful();
      if (result.status == AppUpdateCheckStatus.updateAvailable) {
        await _showRelease(result.release!);
      }
    } on Object catch (error, stackTrace) {
      _logError(error, stackTrace);
    }
  }

  Future<void> runManual() async {
    try {
      final result = await _checker.check();
      await _policy.markSuccessful();
      switch (result.status) {
        case AppUpdateCheckStatus.updateAvailable:
          await _showRelease(result.release!);
        case AppUpdateCheckStatus.upToDate:
          _showToast('当前已是最新正式版');
        case AppUpdateCheckStatus.localAhead:
          _showToast('当前为高于正式版的测试版本');
      }
    } on Object catch (error, stackTrace) {
      _logError(error, stackTrace);
      _showToast('检查更新失败，请稍后重试');
    }
  }
}
