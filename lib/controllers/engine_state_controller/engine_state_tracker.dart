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

/// Pure resolver — no Flutter, no persistence.
EngineState resolveEngineState(
  Map<String, dynamic>? attributes, {
  String? pendingCommandType,
  bool inferFromRelayResult = false,
  bool useIgnitionFallback = false,
}) {
  if (attributes == null) return EngineState.unknown;

  // a) PRIMARY — non-null blocked
  if (attributes.containsKey('blocked') && attributes['blocked'] != null) {
    final blocked = _asBool(attributes['blocked']);
    if (blocked == true) return EngineState.off;
    if (blocked == false) return EngineState.on;
  }

  // b) FALLBACK — result while a command is pending
  if (pendingCommandType != null &&
      attributes.containsKey('result') &&
      attributes['result'] != null) {
    final lower = attributes['result'].toString().toLowerCase();
    final success = lower.contains('ok') || lower.contains('success');
    final hardFail = lower.contains('error') || lower.contains('fail');
    if (success && !hardFail) {
      return pendingCommandType == 'engineStop'
          ? EngineState.off
          : EngineState.on;
    }
    return EngineState.commandFailed;
  }

  // b2) REST load only — Type A devices often leave last result as
  // "RELAY 0 OK" / "RELAY 1 OK" without a blocked key on that message.
  if (inferFromRelayResult &&
      attributes.containsKey('result') &&
      attributes['result'] != null) {
    final fromRelay = _relayResultToState(attributes['result'].toString());
    if (fromRelay != null) return fromRelay;
  }

  // c) Ignition fallback — only when explicitly enabled for no-relay devices
  if (useIgnitionFallback &&
      attributes.containsKey('ignition') &&
      attributes['ignition'] != null) {
    final ign = _asBool(attributes['ignition']);
    if (ign == true) return EngineState.on;
    if (ign == false) return EngineState.off;
  }

  // d) Do not invent ON/OFF from other fields
  return EngineState.unknown;
}

/// RELAY 1 OK → cut/off, RELAY 0 OK → resume/on (from live device 1797 logs).
EngineState? _relayResultToState(String result) {
  final lower = result.toLowerCase();
  if (!(lower.contains('ok') || lower.contains('success'))) return null;
  final relay1 = RegExp(r'relay\s*1\b').hasMatch(lower);
  final relay0 = RegExp(r'relay\s*0\b').hasMatch(lower);
  if (relay1) return EngineState.off;
  if (relay0) return EngineState.on;
  return null;
}

bool? _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase().trim();
    if (lower == 'true' || lower == '1' || lower == 'on') return true;
    if (lower == 'false' || lower == '0' || lower == 'off') return false;
  }
  return null;
}

/// In-memory engine-state tracker (no disk). Unit-testable.
class EngineStateTracker {
  EngineStateTracker({
    Stopwatch? stopwatch,
    this.pendingTimeout = const Duration(seconds: 30),
  }) : _mono = stopwatch ?? (Stopwatch()..start());

  final Stopwatch _mono;
  final Duration pendingTimeout;

  final Map<int, EngineState> _states = {};
  /// Session-only last on/off (for commandFailed UI). Never persisted.
  final Map<int, EngineState> _lastConfirmed = {};
  final Map<int, PendingEngineCommand> _pending = {};
  final Map<int, DateTime> _lastAppliedAt = {};
  /// Devices that never report blocked/RELAY — local Stop/Resume (+ first-paint ignition).
  final Set<int> _ignitionMode = {};
  /// Once true, live ignition must not overwrite local ON/OFF for this device.
  final Set<int> _localCommandLocked = {};
  /// Seen real `blocked` this session — never use local-command mode for these.
  final Set<int> _hadBlocked = {};
  /// Protocol ct3 — immobilizer via `blocked`; default ON when missing.
  final Set<int> _ct3Devices = {};

  EngineState stateOf(int deviceId) =>
      _states[deviceId] ?? EngineState.unknown;

  EngineState? lastConfirmedOf(int deviceId) => _lastConfirmed[deviceId];

  PendingEngineCommand? pendingOf(int deviceId) => _pending[deviceId];

  DateTime? lastAppliedAt(int deviceId) => _lastAppliedAt[deviceId];

  bool usesIgnitionFallback(int deviceId) => _ignitionMode.contains(deviceId);

  /// True only after Traccar sent a real `blocked` value for this device.
  bool reportsBlocked(int deviceId) => _hadBlocked.contains(deviceId);

  bool isCt3(int deviceId) => _ct3Devices.contains(deviceId);

  void noteProtocol(int deviceId, String? protocol) {
    if ((protocol ?? '').toLowerCase() == 'ct3') {
      _ct3Devices.add(deviceId);
    }
  }

  /// Restore session memory from disk (survives app restart).
  /// Does not overwrite an in-memory ON/OFF (e.g. after Stop/Resume).
  void seedBlockedFromCache(
    int deviceId, {
    required bool reportsBlocked,
    EngineState? state,
  }) {
    if (reportsBlocked) {
      _hadBlocked.add(deviceId);
      _ignitionMode.remove(deviceId);
    }
    final current = _states[deviceId];
    if (current == EngineState.on || current == EngineState.off) {
      return;
    }
    if (state == EngineState.on || state == EngineState.off) {
      _lastConfirmed[deviceId] = state!;
      _states[deviceId] = state;
    }
  }

  /// Restore last Stop/Resume when live `blocked` is missing.
  void seedCommandFromCache(int deviceId, String? commandType) {
    if (commandType != 'engineStop' && commandType != 'engineResume') {
      return;
    }
    final current = _states[deviceId];
    if (current == EngineState.on || current == EngineState.off) {
      // applyInitialSnapshot still prefers [lastEngineCommand] when blocked is null.
      return;
    }
    _localCommandLocked.add(deviceId);
    final state =
        commandType == 'engineStop' ? EngineState.off : EngineState.on;
    _lastConfirmed[deviceId] = state;
    _states[deviceId] = state;
  }

  EngineState? _stateFromCommand(String? commandType) {
    if (commandType == 'engineStop') return EngineState.off;
    if (commandType == 'engineResume') return EngineState.on;
    return null;
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

  /// POST /commands/send failed — clear pending, restore last known ON/OFF.
  void failCommandSend(int deviceId) {
    _clearPending(deviceId);
    final confirmed = _lastConfirmed[deviceId];
    if (confirmed == EngineState.on || confirmed == EngineState.off) {
      _states[deviceId] = confirmed!;
    } else {
      _states[deviceId] = EngineState.unknown;
    }
  }

  /// Apply position/device attributes. Newer [timestamp] always wins (REST vs WS).
  ///
  /// When resolve returns [EngineState.unknown] and we are not pending,
  /// keeps the previous on/off instead of flickering (most GPS updates omit
  /// blocked/result). Initial REST load should call [applyInitialSnapshot].
  bool onPositionUpdate({
    required int deviceId,
    Map<String, dynamic>? attributes,
    DateTime? timestamp,
    String? protocol,
    String? lastEngineCommand,
  }) {
    noteProtocol(deviceId, protocol);

    final pendingType = _pending[deviceId]?.commandType;
    final hasBlocked = attributes != null &&
        attributes.containsKey('blocked') &&
        attributes['blocked'] != null;

    // `blocked` is authoritative for immobilizer — accept equal/newer times.
    if (hasBlocked) {
      _hadBlocked.add(deviceId);
      _ignitionMode.remove(deviceId);
      _localCommandLocked.remove(deviceId);
      if (timestamp != null) {
        final last = _lastAppliedAt[deviceId];
        if (last != null && timestamp.isBefore(last)) {
          return false;
        }
        _lastAppliedAt[deviceId] = timestamp;
      }
    } else if (!_acceptTimestamp(deviceId, timestamp)) {
      return false;
    }

    final resolved = resolveEngineState(
      attributes,
      pendingCommandType: pendingType,
      // ct3: honor RELAY 0/1 when blocked omitted — but not stale RELAY
      // after a newer local Stop/Resume (see match below).
      inferFromRelayResult: _ct3Devices.contains(deviceId) &&
          !_localCommandLocked.contains(deviceId),
      useIgnitionFallback: false,
    );

    if (resolved == EngineState.on || resolved == EngineState.off) {
      _clearPending(deviceId);
      return _setConfirmed(deviceId, resolved);
    }

    // Stale RELAY while waiting for device: only accept RELAY that matches
    // the command we just confirmed locally (RELAY 1 after Stop, 0 after Resume).
    if (_ct3Devices.contains(deviceId) &&
        _localCommandLocked.contains(deviceId) &&
        attributes != null &&
        attributes['result'] != null) {
      final fromRelay = _relayResultToState(attributes['result'].toString());
      final expected = _lastConfirmed[deviceId];
      if (fromRelay != null && fromRelay == expected) {
        _localCommandLocked.remove(deviceId);
        _clearPending(deviceId);
        return _setConfirmed(deviceId, fromRelay);
      }
    }

    if (resolved == EngineState.commandFailed) {
      _clearPending(deviceId);
      final prev = _states[deviceId];
      _states[deviceId] = EngineState.commandFailed;
      return prev != EngineState.commandFailed;
    }

    // No blocked on this packet: prefer last Stop/Resume, else keep / default ON.
    if (_ct3Devices.contains(deviceId) && pendingType == null) {
      final fromCmd = _stateFromCommand(lastEngineCommand);
      if (fromCmd != null) {
        return _setConfirmed(deviceId, fromCmd);
      }
      final prev = _states[deviceId];
      if (prev == EngineState.on || prev == EngineState.off) {
        return false;
      }
      return _setConfirmed(deviceId, EngineState.on);
    }

    if (pendingType != null) {
      return false;
    }
    return false;
  }

  /// REST load / first paint — may set unknown when nothing authoritative.
  /// Does **not** lock [timestamp] when result is unknown, so a later history
  /// backfill (older message with `blocked`) can still apply.
  bool applyInitialSnapshot({
    required int deviceId,
    Map<String, dynamic>? positionAttributes,
    Map<String, dynamic>? deviceAttributes,
    DateTime? timestamp,
    String? protocol,
    String? lastEngineCommand,
  }) {
    noteProtocol(deviceId, protocol);

    final hasBlocked = (positionAttributes != null &&
            positionAttributes.containsKey('blocked') &&
            positionAttributes['blocked'] != null) ||
        (deviceAttributes != null &&
            deviceAttributes.containsKey('blocked') &&
            deviceAttributes['blocked'] != null);
    if (hasBlocked) {
      _hadBlocked.add(deviceId);
      _ignitionMode.remove(deviceId);
      _localCommandLocked.remove(deviceId);
    }

    // ct1 local mode: keep Stop/Resume (or first ignition snapshot) — do not
    // re-apply live ignition from REST polls.
    final prevLocked = _states[deviceId];
    if (_ignitionMode.contains(deviceId) &&
        (prevLocked == EngineState.on || prevLocked == EngineState.off)) {
      return false;
    }

    var attrs = positionAttributes;
    final fromPos = resolveEngineState(
      attrs,
      inferFromRelayResult: !_localCommandLocked.contains(deviceId),
      useIgnitionFallback: false,
    );
    if (fromPos == EngineState.on || fromPos == EngineState.off) {
      if (timestamp != null) {
        final last = _lastAppliedAt[deviceId];
        if (last != null && timestamp.isBefore(last)) {
          return false;
        }
        _lastAppliedAt[deviceId] = timestamp;
      }
      return _setConfirmed(deviceId, fromPos);
    }

    // Matching RELAY after local command unlocks and confirms.
    if (_localCommandLocked.contains(deviceId) &&
        positionAttributes != null &&
        positionAttributes['result'] != null) {
      final fromRelay =
          _relayResultToState(positionAttributes['result'].toString());
      final expected = _lastConfirmed[deviceId];
      if (fromRelay != null && fromRelay == expected) {
        _localCommandLocked.remove(deviceId);
        if (timestamp != null) _lastAppliedAt[deviceId] = timestamp;
        return _setConfirmed(deviceId, fromRelay);
      }
    }

    attrs = deviceAttributes;
    final fromDev = resolveEngineState(
      attrs,
      inferFromRelayResult: !_localCommandLocked.contains(deviceId),
      useIgnitionFallback: false,
    );
    if (fromDev == EngineState.on || fromDev == EngineState.off) {
      if (timestamp != null) {
        final last = _lastAppliedAt[deviceId];
        if (last != null && timestamp.isBefore(last)) {
          return false;
        }
        _lastAppliedAt[deviceId] = timestamp;
      }
      return _setConfirmed(deviceId, fromDev);
    }

    // ct3 + no blocked: last Stop/Resume wins over stale memory/cache.
    if (_ct3Devices.contains(deviceId)) {
      final fromCmd = _stateFromCommand(lastEngineCommand);
      if (fromCmd != null) {
        _localCommandLocked.add(deviceId);
        return _setConfirmed(deviceId, fromCmd);
      }
      final prev = _states[deviceId];
      if (prev == EngineState.on || prev == EngineState.off) {
        return false;
      }
      return _setConfirmed(deviceId, EngineState.on);
    }

    final prev = _states[deviceId];
    if (prev == EngineState.pending ||
        prev == EngineState.unconfirmed ||
        prev == EngineState.commandFailed ||
        prev == EngineState.on ||
        prev == EngineState.off ||
        prev == EngineState.noRelayData) {
      return false;
    }
    _states[deviceId] = EngineState.unknown;
    return prev != EngineState.unknown;
  }

  /// Apply newest-first history until a real on/off is found (REST backfill).
  bool applyHistoryNewestFirst({
    required int deviceId,
    required List<({Map<String, dynamic>? attributes, DateTime? timestamp})>
        positionsNewestFirst,
  }) {
    for (final p in positionsNewestFirst) {
      final resolved = resolveEngineState(
        p.attributes,
        inferFromRelayResult: true,
      );
      if (resolved != EngineState.on && resolved != EngineState.off) {
        continue;
      }
      final attrs = p.attributes;
      if (attrs != null &&
          attrs.containsKey('blocked') &&
          attrs['blocked'] != null) {
        _hadBlocked.add(deviceId);
        _ignitionMode.remove(deviceId);
        _localCommandLocked.remove(deviceId);
      }
      if (!_acceptTimestamp(deviceId, p.timestamp)) continue;
      return _setConfirmed(deviceId, resolved);
    }
    return false;
  }

  bool onDeviceStatus({required int deviceId, String? status}) {
    if (status?.toLowerCase() != 'offline') return false;
    if (!_pending.containsKey(deviceId)) return false;
    _clearPending(deviceId);
    _states[deviceId] = EngineState.unconfirmed;
    return true;
  }

  bool checkTimeouts() {
    final now = _mono.elapsedMilliseconds;
    var changed = false;
    final expired = _pending.entries
        .where((e) => now >= e.value.deadlineMonoMs)
        .map((e) => e.key)
        .toList();
    for (final deviceId in expired) {
      final pending = _pending[deviceId];
      _clearPending(deviceId);
      // No live blocked yet: confirm from the command we sent (ct1 / ct3).
      if (pending != null &&
          (_ignitionMode.contains(deviceId) ||
              _ct3Devices.contains(deviceId))) {
        final local = pending.commandType == 'engineStop'
            ? EngineState.off
            : EngineState.on;
        _setConfirmed(deviceId, local);
      } else {
        _states[deviceId] = EngineState.unconfirmed;
      }
      changed = true;
    }
    return changed;
  }

  /// Accept update if it is not older than the last applied timestamp.
  bool _acceptTimestamp(int deviceId, DateTime? timestamp) {
    if (timestamp == null) {
      // Null time cannot beat a known newer WS/REST timestamp.
      if (_lastAppliedAt.containsKey(deviceId)) return false;
      return true;
    }
    final last = _lastAppliedAt[deviceId];
    if (last != null && timestamp.isBefore(last)) {
      return false;
    }
    _lastAppliedAt[deviceId] = timestamp;
    return true;
  }

  /// After history finds no blocked/RELAY — local mode for ct1 devices.
  /// Prefer last Stop/Resume command; else one-time ignition for first paint.
  bool enableIgnitionFallback(
    int deviceId, {
    Map<String, dynamic>? attributes,
    String? lastEngineCommand,
  }) {
    if (_pending.containsKey(deviceId)) return false;
    final prev = _states[deviceId];
    if (prev == EngineState.on || prev == EngineState.off) {
      if (!_ignitionMode.contains(deviceId)) return false;
      // Already have local ON/OFF for this no-relay device — keep it.
      return false;
    }

    _ignitionMode.add(deviceId);

    if (lastEngineCommand == 'engineStop') {
      _localCommandLocked.add(deviceId);
      return _setConfirmed(deviceId, EngineState.off);
    }
    if (lastEngineCommand == 'engineResume') {
      _localCommandLocked.add(deviceId);
      return _setConfirmed(deviceId, EngineState.on);
    }

    final fromIgn = resolveEngineState(
      attributes,
      useIgnitionFallback: true,
    );
    if (fromIgn == EngineState.on || fromIgn == EngineState.off) {
      return _setConfirmed(deviceId, fromIgn);
    }
    _states[deviceId] = EngineState.noRelayData;
    return prev != EngineState.noRelayData;
  }

  /// After Stop/Resume accepted: show command status immediately when
  /// live `blocked` is missing. A later non-null `blocked` overwrites this.
  bool confirmLocalCommand(int deviceId, String commandType) {
    _ignitionMode.add(deviceId);
    _localCommandLocked.add(deviceId);
    _clearPending(deviceId);
    final state =
        commandType == 'engineStop' ? EngineState.off : EngineState.on;
    return _setConfirmed(deviceId, state);
  }

  bool _setConfirmed(int deviceId, EngineState state) {
    assert(state == EngineState.on || state == EngineState.off);
    final prev = _states[deviceId];
    final prevConfirmed = _lastConfirmed[deviceId];
    _lastConfirmed[deviceId] = state;
    _states[deviceId] = state;
    return prev != state || prevConfirmed != state;
  }

  /// Devices that currently have a confirmed blocked-based ON/OFF.
  Iterable<int> get devicesWithBlockedReport => _hadBlocked;

  void _clearPending(int deviceId) {
    _pending.remove(deviceId);
  }
}
