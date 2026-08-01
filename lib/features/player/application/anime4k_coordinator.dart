import 'package:kanyingyin/features/player/application/anime4k_policy.dart';
import 'package:synchronized/synchronized.dart';

typedef Anime4kDecisionExecutor = Future<void> Function(
  Anime4kDecision decision,
);

final class Anime4kCoordinator {
  Anime4kCoordinator({
    required Anime4kPolicy policy,
    required Anime4kDecisionExecutor execute,
  })  : _policy = policy,
        _execute = execute;

  final Anime4kPolicy _policy;
  final Anime4kDecisionExecutor _execute;
  final Lock _applyLock = Lock();
  Anime4kAction? _lastAppliedAction;
  bool _failureLocked = false;
  int _stateEpoch = 0;

  Future<Anime4kDecision> evaluateAndApply(
    Anime4kPolicyInput input,
  ) {
    final requestEpoch = _stateEpoch;
    return _applyLock.synchronized(() async {
      if (_failureLocked) {
        return const Anime4kDecision(
          state: Anime4kRuntimeState.failedDisabled,
          action: Anime4kAction.clear,
          scale: 0,
        );
      }
      final decision = _policy.evaluate(input);
      if (_lastAppliedAction == decision.action) return decision;
      try {
        await _execute(decision);
        if (requestEpoch == _stateEpoch) {
          _lastAppliedAction = decision.action;
        }
        return decision;
      } on Object {
        if (requestEpoch == _stateEpoch) {
          _failureLocked = true;
          _lastAppliedAction = Anime4kAction.clear;
        }
        return Anime4kDecision(
          state: Anime4kRuntimeState.failedDisabled,
          action: Anime4kAction.clear,
          scale: decision.scale,
        );
      }
    });
  }

  void resetFailureLock() {
    _stateEpoch++;
    _failureLocked = false;
    _lastAppliedAction = null;
  }

  void reset() {
    _stateEpoch++;
    _failureLocked = false;
    _lastAppliedAction = null;
  }
}
