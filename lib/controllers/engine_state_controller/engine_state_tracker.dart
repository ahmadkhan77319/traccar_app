import '../../model/engine_state/engine_state.dart';

class PendingEngineCommand {
  PendingEngineCommand({
    required this.deviceId,
    required this.commandType,
    required this.sentAtMonoMs,
    required this.deadlineMonoMs,
  });

  final int deviceId;

  /// `engineStop` or `engineResume`
  final String commandType;

  /// Monotonic elapsed ms when the command was marked pending.
  final int sentAtMonoMs;

  /// Monotonic elapsed ms when the pending command expires.
  final int deadlineMonoMs;
}

/// Pure engine-state resolver (no Flutter / GetX). Unit-testable.
class EngineStateTracker {
  EngineStateTracker({
    Stopwatch? stopwatch,
    this.pendingTimeout = const Duration(seconds: 30),
  }) : _mono = stopwatch ?? (Stopwatch()..start());

  final Stopwatch _mono;
  final Duration pendingTimeout;

  final Map<int, EngineState> _states = {};
  final Map<int, EngineState> _lastConfirmed = {};
  final Map<int, PendingEngineCommand> _pending = {};
  final Map<int, DateTime> _lastAppliedAt = {};

  /// Live display state (may be pending / unconfirmed / commandFailed).
  EngineState stateOf(int deviceId) =>
      _states[deviceId] ?? EngineState.unknown;

  /// Last confirmed on/off only (never pending/failed/unconfirmed).
  EngineState? lastConfirmedOf(int deviceId) => _lastConfirmed[deviceId];

  PendingEngineCommand? pendingOf(int deviceId) => _pending[deviceId];

  Map<int, EngineState> get confirmedSnapshot =>
      Map<int, EngineState>.unmodifiable(_lastConfirmed);

  /// Seed confirmed state from persistence (on / off only).
  void seedConfirmed(int deviceId, EngineState state) {
    if (state != EngineState.on && state != EngineState.off) return;
    _lastConfirmed[deviceId] = state;
    _states[deviceId] = state;
  }

  /// Mark command pending *before* HTTP completes. Replaces any prior pending.
  void markCommandPending(int deviceId, String commandType) {
    final now = _mono.elapsedMilliseconds;
    _pending[deviceId] = PendingEngineCommand(
      deviceId: deviceId,
      commandType: commandType,
      sentAtMonoMs: now,
      deadlineMonoMs: now + pendingTimeout.inMilliseconds,
    );
    _states[deviceId] = EngineState.pending;
  }

  /// Apply a position update. Returns true if display state changed.
  bool onPositionUpdate({
    required int deviceId,
    Map<String, dynamic>? attributes,
    DateTime? timestamp,
  }) {
    if (timestamp != null) {
      final last = _lastAppliedAt[deviceId];
      if (last != null && timestamp.isBefore(last)) {
        return false;
      }
      _lastAppliedAt[deviceId] = timestamp;
    }

    final attrs = attributes;
    if (attrs == null) return false;

    // 1) PRIMARY — non-null blocked key
    if (attrs.containsKey('blocked') && attrs['blocked'] != null) {
      final blocked = _asBool(attrs['blocked']);
      if (blocked != null) {
        _clearPending(deviceId);
        return _setConfirmed(
          deviceId,
          blocked ? EngineState.off : EngineState.on,
        );
      }
    }

    // 2) FALLBACK — result + pending command
    final pending = _pending[deviceId];
    if (pending == null) return false;

    if (!attrs.containsKey('result') || attrs['result'] == null) {
      return false;
    }

    final result = attrs['result'].toString();
    final lower = result.toLowerCase();
    final success = lower.contains('ok') || lower.contains('success');
    final hardFail = lower.contains('error') || lower.contains('fail');

    if (success && !hardFail) {
      final next = pending.commandType == 'engineStop'
          ? EngineState.off
          : EngineState.on;
      _clearPending(deviceId);
      return _setConfirmed(deviceId, next);
    }

    // Failure / non-OK result
    _clearPending(deviceId);
    _states[deviceId] = EngineState.commandFailed;
    return true;
  }

  /// Device went offline while a command was pending → unconfirmed.
  bool onDeviceStatus({required int deviceId, String? status}) {
    if (status?.toLowerCase() != 'offline') return false;
    if (!_pending.containsKey(deviceId)) return false;
    _clearPending(deviceId);
    _states[deviceId] = EngineState.unconfirmed;
    return true;
  }

  /// Wall-monotonic deadline check (safe after app resume).
  bool checkTimeouts() {
    final now = _mono.elapsedMilliseconds;
    var changed = false;
    final expired = _pending.entries
        .where((e) => now >= e.value.deadlineMonoMs)
        .map((e) => e.key)
        .toList();
    for (final deviceId in expired) {
      _clearPending(deviceId);
      _states[deviceId] = EngineState.unconfirmed;
      changed = true;
    }
    return changed;
  }

  bool _setConfirmed(int deviceId, EngineState state) {
    assert(state == EngineState.on || state == EngineState.off);
    final prev = _states[deviceId];
    final prevConfirmed = _lastConfirmed[deviceId];
    _lastConfirmed[deviceId] = state;
    _states[deviceId] = state;
    return prev != state || prevConfirmed != state;
  }

  void _clearPending(int deviceId) {
    _pending.remove(deviceId);
  }

  static bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == 'true' || lower == '1' || lower == 'on') return true;
      if (lower == 'false' || lower == '0' || lower == 'off') return false;
    }
    return null;
  }
}
