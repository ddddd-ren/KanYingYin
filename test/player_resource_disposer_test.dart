import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_resource_disposer.dart';

void main() {
  test('释放步骤失败时继续执行剩余步骤并返回失败', () async {
    final calls = <String>[];
    final failures = await const PlayerResourceDisposer().dispose(
      <PlayerDisposeStep>[
        () async {
          calls.add('subscription');
          throw StateError('cancel failed');
        },
        () async => calls.add('debug'),
        () async => calls.add('player'),
      ],
    );

    expect(calls, <String>['subscription', 'debug', 'player']);
    expect(failures, hasLength(1));
    expect(failures.single.stepIndex, 0);
    expect(failures.single.error, isA<StateError>());
  });
}
