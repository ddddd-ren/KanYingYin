import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/android/android_performance_profile.dart';

void main() {
  test('MT6877 SoC 优先命中天玑 930 专项档位', () {
    expect(
      AndroidPerformanceProfileResolver.resolve(
        manufacturer: 'vivo',
        model: 'V2219A',
        hardware: 'mt6877',
        socModel: 'MT6877V/TTZA',
      ),
      AndroidPerformanceProfile.mt6877,
    );
  });

  test('vivo PD2219 在 SoC 字段缺失时回退命中专项档位', () {
    expect(
      AndroidPerformanceProfileResolver.resolve(
        manufacturer: 'vivo',
        model: 'PD2219',
        hardware: 'unknown',
        socModel: '',
      ),
      AndroidPerformanceProfile.mt6877,
    );
  });

  test('近似型号和其他芯片保持标准档位', () {
    for (final profile in <AndroidPerformanceProfile>[
      AndroidPerformanceProfileResolver.resolve(
        manufacturer: 'xiaomi',
        model: '17 Pro',
        hardware: 'qcom',
        socModel: 'SM8850',
      ),
      AndroidPerformanceProfileResolver.resolve(
        manufacturer: 'vivo',
        model: 'PD2218',
        hardware: 'unknown',
        socModel: '',
      ),
    ]) {
      expect(profile, AndroidPerformanceProfile.standard);
    }
  });
}
