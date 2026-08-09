enum AndroidPerformanceProfile { standard, mt6877 }

abstract final class AndroidPerformanceProfileResolver {
  static AndroidPerformanceProfile resolve({
    required String manufacturer,
    required String model,
    required String hardware,
    required String socModel,
  }) {
    final chip = '$hardware $socModel'.toLowerCase();
    if (chip.contains('mt6877')) return AndroidPerformanceProfile.mt6877;

    final maker = manufacturer.trim().toLowerCase();
    final device = model.trim().toLowerCase();
    if (maker == 'vivo' && device.contains('pd2219')) {
      return AndroidPerformanceProfile.mt6877;
    }
    return AndroidPerformanceProfile.standard;
  }
}
