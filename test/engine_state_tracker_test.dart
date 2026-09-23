import 'package:flutter_test/flutter_test.dart';
import 'package:traccar_app/controllers/engine_state_controller/engine_state_tracker.dart';
import 'package:traccar_app/model/engine_state/engine_state.dart';

void main() {
  group('resolveEngineState', () {
    test('blocked-present: true → off, false → on', () {
      expect(
        resolveEngineState({'blocked': true}),
        EngineState.off,
      );
      expect(
        resolveEngineState({'blocked': false}),
        EngineState.on,
      );
    });

    test('result-fallback success', () {
      expect(
        resolveEngineState(
          {'result': 'S20,OK,143912'},
          pendingCommandType: 'engineStop',
        ),
        EngineState.off,
      );
      expect(
        resolveEngineState(
          {'result': 'RELAY 1 OK'},
          pendingCommandType: 'engineResume',
        ),
        EngineState.on,
      );
    });

    test('result-fallback failure', () {
      expect(
        resolveEngineState(
          {'result': 'S20,ERROR'},
          pendingCommandType: 'engineStop',
        ),
        EngineState.commandFailed,
      );
      expect(
        resolveEngineState(
          {'result': 'FAIL'},
          pendingCommandType: 'engineResume',
        ),
        EngineState.commandFailed,
      );
    });

    test('REST infers ON/OFF from RELAY 0/1 OK without pending', () {
      expect(
        resolveEngineState(
          {'result': 'RELAY 0 OK'},
          inferFromRelayResult: true,
        ),
        EngineState.on,
      );
      expect(
        resolveEngineState(
          {'result': 'RELAY 1 OK'},
          inferFromRelayResult: true,
        ),
        EngineState.off,
      );
      // Without flag, must stay unknown
      expect(
        resolveEngineState({'result': 'RELAY 0 OK'}),
        EngineState.unknown,
      );
    });

    test('unknown when neither blocked nor pending result', () {
      expect(
        resolveEngineState({'ignition': true, 'motion': false}),
        EngineState.unknown,
      );
      expect(resolveEngineState(null), EngineState.unknown);
      expect(resolveEngineState({}), EngineState.unknown);
      // result without pending must not invent state
      expect(
        resolveEngineState({'result': 'S20,OK,1'}),
        EngineState.unknown,
      );
    });
  });

  group('EngineStateTracker', () {
    late Stopwatch mono;
    late EngineStateTracker tracker;

    setUp(() {
      mono = Stopwatch()..start();
      tracker = EngineStateTracker(
        stopwatch: mono,
        pendingTimeout: const Duration(seconds: 30),
      );
    });

    test('blocked-present resolution via position update', () {
      tracker.onPositionUpdate(
        deviceId: 1797,
        attributes: {'blocked': true},
        timestamp: DateTime(2026, 9, 22, 12),
      );
      expect(tracker.stateOf(1797), EngineState.off);

      tracker.onPositionUpdate(
        deviceId: 1797,
        attributes: {'blocked': false},
        timestamp: DateTime(2026, 9, 22, 12, 1),
      );
      expect(tracker.stateOf(1797), EngineState.on);
    });

    test('result-fallback success / failure with pending', () {
      tracker.markCommandPending(596, 'engineStop');
      tracker.onPositionUpdate(
        deviceId: 596,
        attributes: {'result': 'S20,OK,143912'},
        timestamp: DateTime(2026, 9, 22, 14),
      );
      expect(tracker.stateOf(596), EngineState.off);

      tracker.seedLastConfirmedForTest(10, EngineState.on);
      tracker.markCommandPending(10, 'engineStop');
      tracker.onPositionUpdate(
        deviceId: 10,
        attributes: {'result': 'ERROR'},
        timestamp: DateTime(2026, 9, 22, 15),
      );
      expect(tracker.stateOf(10), EngineState.commandFailed);
      expect(tracker.lastConfirmedOf(10), EngineState.on);
    });

    test('timeout / unconfirmed', () {
      final fast = EngineStateTracker(
        stopwatch: mono,
        pendingTimeout: const Duration(milliseconds: 1),
      );
      fast.markCommandPending(20, 'engineStop');
      while (mono.elapsedMilliseconds < fast.pendingOf(20)!.deadlineMonoMs) {}
      expect(fast.checkTimeouts(), isTrue);
      expect(fast.stateOf(20), EngineState.unconfirmed);
    });

    test('out-of-order update rejection', () {
      final t1 = DateTime(2026, 9, 22, 10);
      final t0 = DateTime(2026, 9, 22, 9);
      tracker.onPositionUpdate(
        deviceId: 5,
        attributes: {'blocked': true},
        timestamp: t1,
      );
      expect(
        tracker.onPositionUpdate(
          deviceId: 5,
          attributes: {'blocked': false},
          timestamp: t0,
        ),
        isFalse,
      );
      expect(tracker.stateOf(5), EngineState.off);
    });

    test('REST vs WebSocket race — newer timestamp wins', () {
      final restTime = DateTime(2026, 9, 22, 10, 0, 0);
      final wsTime = DateTime(2026, 9, 22, 10, 0, 5);

      // WS arrives first with newer fix
      tracker.onPositionUpdate(
        deviceId: 42,
        attributes: {'blocked': false},
        timestamp: wsTime,
      );
      expect(tracker.stateOf(42), EngineState.on);

      // Late REST snapshot is older → ignored
      expect(
        tracker.applyInitialSnapshot(
          deviceId: 42,
          positionAttributes: {'blocked': true},
          timestamp: restTime,
        ),
        isFalse,
      );
      expect(tracker.stateOf(42), EngineState.on);

      // Reverse: REST first, then older WS rejected
      final t = EngineStateTracker(stopwatch: mono);
      t.applyInitialSnapshot(
        deviceId: 43,
        positionAttributes: {'blocked': true},
        timestamp: wsTime,
      );
      expect(t.stateOf(43), EngineState.off);
      expect(
        t.onPositionUpdate(
          deviceId: 43,
          attributes: {'blocked': false},
          timestamp: restTime,
        ),
        isFalse,
      );
      expect(t.stateOf(43), EngineState.off);
    });

    test('concurrent commands on two devices', () {
      tracker.markCommandPending(100, 'engineStop');
      tracker.markCommandPending(200, 'engineResume');
      tracker.onPositionUpdate(
        deviceId: 100,
        attributes: {'result': 'OK'},
        timestamp: DateTime(2026, 9, 22, 16),
      );
      expect(tracker.stateOf(100), EngineState.off);
      expect(tracker.stateOf(200), EngineState.pending);
      tracker.onPositionUpdate(
        deviceId: 200,
        attributes: {'result': 'SUCCESS'},
        timestamp: DateTime(2026, 9, 22, 16, 1),
      );
      expect(tracker.stateOf(200), EngineState.on);
    });

    test('initial snapshot unknown when no blocked on position or device', () {
      tracker.applyInitialSnapshot(
        deviceId: 1,
        positionAttributes: {'ignition': false},
        deviceAttributes: {'foo': 1},
        timestamp: DateTime(2026, 9, 22),
      );
      expect(tracker.stateOf(1), EngineState.unknown);
    });

    test('GPS update without blocked does not wipe confirmed state', () {
      tracker.onPositionUpdate(
        deviceId: 9,
        attributes: {'blocked': true},
        timestamp: DateTime(2026, 9, 22, 11),
      );
      tracker.onPositionUpdate(
        deviceId: 9,
        attributes: {'ignition': false, 'motion': false},
        timestamp: DateTime(2026, 9, 22, 11, 1),
      );
      expect(tracker.stateOf(9), EngineState.off);
    });

    test('ignition fallback for no-relay devices; blocked still wins for 1797', () {
      expect(tracker.stateOf(504), EngineState.unknown);
      tracker.enableIgnitionFallback(
        504,
        attributes: {'ignition': false, 'status': 1},
      );
      expect(tracker.usesIgnitionFallback(504), isTrue);
      expect(tracker.stateOf(504), EngineState.off);

      // Live ignition ON must NOT overwrite local OFF for ct1.
      tracker.onPositionUpdate(
        deviceId: 504,
        attributes: {'ignition': true, 'motion': true},
        timestamp: DateTime(2026, 9, 22, 18, 1),
      );
      expect(tracker.stateOf(504), EngineState.off);

      // Resume locks ON locally; later ignition false must not flip to OFF.
      expect(tracker.confirmLocalCommand(504, 'engineResume'), isTrue);
      expect(tracker.stateOf(504), EngineState.on);
      tracker.onPositionUpdate(
        deviceId: 504,
        attributes: {'ignition': false},
        timestamp: DateTime(2026, 9, 22, 18, 2),
      );
      expect(tracker.stateOf(504), EngineState.on);

      tracker.onPositionUpdate(
        deviceId: 1797,
        attributes: {'blocked': false, 'ignition': false},
        timestamp: DateTime(2026, 9, 22, 18),
      );
      expect(tracker.stateOf(1797), EngineState.on);
      expect(tracker.usesIgnitionFallback(1797), isFalse);
      expect(tracker.confirmLocalCommand(1797, 'engineStop'), isFalse);
      expect(tracker.stateOf(1797), EngineState.on);

      tracker.enableIgnitionFallback(
        596,
        lastEngineCommand: 'engineResume',
        attributes: {'ignition': false},
      );
      expect(tracker.stateOf(596), EngineState.on);
    });
  });
}

/// Test-only hook — keeps lastConfirmed for failure UI without persistence.
extension on EngineStateTracker {
  void seedLastConfirmedForTest(int deviceId, EngineState state) {
    onPositionUpdate(
      deviceId: deviceId,
      attributes: {
        'blocked': state == EngineState.off,
      },
      timestamp: DateTime(2026, 1, 1),
    );
  }
}
