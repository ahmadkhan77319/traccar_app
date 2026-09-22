import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../model/engine_state/engine_state.dart';
import '../../repositories/shared_pref_repo.dart';
import 'engine_state_tracker.dart';

/// GetX façade over [EngineStateTracker] with persistence + lifecycle deadlines.
class EngineStateController extends GetxController with WidgetsBindingObserver {
  EngineStateController({
    SharedPrefsRepository? prefs,
    EngineStateTracker? tracker,
  })  : _prefs = prefs ?? SharedPrefsRepository(),
        tracker = tracker ?? EngineStateTracker();

  final SharedPrefsRepository _prefs;
  final EngineStateTracker tracker;

  /// Per-device reactive states for Obx.
  final Map<int, Rx<EngineState>> _rxStates = {};

  /// Bumps when any device state changes (list screens can Obx this).
  final revision = 0.obs;

  Timer? _deadlinePoll;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _hydrateFromPrefs();
    // Poll monotonic deadlines (Timers can be delayed while suspended).
    _deadlinePoll = Timer.periodic(const Duration(seconds: 2), (_) {
      _flushTimeouts();
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _deadlinePoll?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _flushTimeouts();
    }
  }

  /// Reactive getter — safe for multiple device screens at once.
  Rx<EngineState> engineStateFor(int deviceId) {
    return _rxStates.putIfAbsent(
      deviceId,
      () => tracker.stateOf(deviceId).obs,
    );
  }

  EngineState stateOf(int deviceId) => tracker.stateOf(deviceId);

  /// Last confirmed on/off (for UI when state is commandFailed / unconfirmed).
  EngineState? lastConfirmedOf(int deviceId) =>
      tracker.lastConfirmedOf(deviceId);

  String labelFor(int deviceId) {
    switch (stateOf(deviceId)) {
      case EngineState.on:
        return 'Engine ON';
      case EngineState.off:
        return 'Engine OFF';
      case EngineState.pending:
        return 'Command pending…';
      case EngineState.unconfirmed:
        return 'Unconfirmed';
      case EngineState.commandFailed:
        return 'Command failed';
      case EngineState.unknown:
        return 'Engine Status Unknown';
    }
  }

  /// Call when user taps Stop/Resume — *before* awaiting HTTP.
  void markCommandPending(int deviceId, String commandType) {
    tracker.markCommandPending(deviceId, commandType);
    _syncRx(deviceId);
  }

  void onPositionUpdate({
    required int deviceId,
    Map<String, dynamic>? attributes,
    DateTime? deviceTime,
    DateTime? fixTime,
    DateTime? serverTime,
  }) {
    final ts = deviceTime ?? fixTime ?? serverTime;
    final beforeConfirmed = tracker.lastConfirmedOf(deviceId);
    final changed = tracker.onPositionUpdate(
      deviceId: deviceId,
      attributes: attributes,
      timestamp: ts,
    );
    if (!changed) return;

    final afterConfirmed = tracker.lastConfirmedOf(deviceId);
    if (afterConfirmed != null && afterConfirmed != beforeConfirmed) {
      _prefs.setConfirmedEngineState(deviceId, afterConfirmed.name);
    }
    _syncRx(deviceId);
  }

  void onDeviceStatus({required int deviceId, String? status}) {
    final changed = tracker.onDeviceStatus(deviceId: deviceId, status: status);
    if (changed) _syncRx(deviceId);
  }

  void _hydrateFromPrefs() {
    final stored = _prefs.allConfirmedEngineStates();
    for (final entry in stored.entries) {
      final state = entry.value == 'on'
          ? EngineState.on
          : (entry.value == 'off' ? EngineState.off : null);
      if (state == null) continue;
      tracker.seedConfirmed(entry.key, state);
      _syncRx(entry.key, bump: false);
    }
    if (stored.isNotEmpty) revision.value++;
  }

  void _flushTimeouts() {
    if (!tracker.checkTimeouts()) return;
    for (final id in _rxStates.keys) {
      _syncRx(id, bump: false);
    }
    revision.value++;
  }

  void _syncRx(int deviceId, {bool bump = true}) {
    final rx = engineStateFor(deviceId);
    rx.value = tracker.stateOf(deviceId);
    if (bump) revision.value++;
  }
}
