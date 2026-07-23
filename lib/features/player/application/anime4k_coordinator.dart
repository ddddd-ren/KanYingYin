import 'package:kanyingyin/features/player/application/anime4k_policy.dart';

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
  Anime4kAction? _lastAppliedAction;
  bool _failureLocked = false;

  Future<Anime4kDecision> evaluateAndApply(
    Anime4kPolicyInput input,
  ) async {
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
      _lastAppliedAction = decision.action;
      return decision;
    } on Object {
      _failureLocked = true;
      _lastAppliedAction = Anime4kAction.clear;
      return Anime4kDecision(
        state: Anime4kRuntimeState.failedDisabled,
        action: Anime4kAction.clear,
        scale: decision.scale,
      );
    }
  }

  void resetFailureLock() {
    _failureLocked = false;
    _lastAppliedAction = null;
  }

  void reset() {
    _failureLocked = false;
    _lastAppliedAction = null;
  }
}
