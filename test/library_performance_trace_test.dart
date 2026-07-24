import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/library_performance_trace.dart';

void main() {
  test('性能追踪只记录固定阶段、数量和耗时', () {
    final messages = <String>[];
    final trace = LibraryPerformanceTrace(log: messages.add);

    final result = trace.measure(
      LibraryPerformanceStage.localIndexRead,
      () => [r'D:\Private\Secret Movie.mkv'],
      count: (items) => items.length,
    );

    expect(result, hasLength(1));
    expect(messages.single, contains('stage=local-index-read'));
    expect(messages.single, contains('count=1'));
    expect(messages.single, contains('elapsedMs='));
    expect(messages.single, isNot(contains('Private')));
    expect(messages.single, isNot(contains('Secret Movie')));
  });

  test('异步性能追踪返回原结果', () async {
    final messages = <String>[];
    final trace = LibraryPerformanceTrace(log: messages.add);

    final result = await trace.measureAsync(
      LibraryPerformanceStage.cloudIndexRead,
      () async => const <int>[1, 2],
      count: (items) => items.length,
    );

    expect(result, [1, 2]);
    expect(messages.single, contains('stage=cloud-index-read'));
    expect(messages.single, contains('count=2'));
  });
}
