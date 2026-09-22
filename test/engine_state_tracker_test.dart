import 'package:flutter_test/flutter_test.dart';
import 'package:traccar_app/controllers/engine_state_controller/engine_state_tracker.dart';
import 'package:traccar_app/model/engine_state/engine_state.dart';

void main() {
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

    test('blocked-present: true → off, false → on', () {
      tracker.onPositionUpdate(
        deviceId: 1797,
        attributes: {'blocked': true, 'ignition': false},
        timestamp: DateTime(2026, 9, 22, 12),
      );
      expect(tracker.stateOf(1797), EngineState.off);
      expect(tracker.lastConfirmedOf(1797), EngineState.off);

      tracker.onPositionUpdate(
        deviceId: 1797,
        attributes: {'blocked': false, 'ignition': false},
        timestamp: DateTime(2026, 9, 22, 12, 1),
      );
      expect(tracker.stateOf(1797), EngineState.on);
      expect(tracker.lastConfirmedOf(1797), EngineState.on);
    });

    test('result-fallback success for engineStop / engineResume', () {
      tracker.markCommandPending(596, 'engineStop');
      expect(tracker.stateOf(596), EngineState.pending);

      tracker.onPositionUpdate(
        deviceId: 596,
        attributes: {'result': 'S20,OK,143912', 'ignition': false},
        timestamp: DateTime(2026, 9, 22, 14),
      );
      expect(tracker.stateOf(596), EngineState.off);
      expect(tracker.pendingOf(596), isNull);

      tracker.markCommandPending(596, 'engineResume');
      tracker.onPositionUpdate(
        deviceId: 596,
        attributes: {'result': 'RELAY 1 OK'},
        timestamp: DateTime(2026, 9, 22, 14, 1),
      );
      expect(tracker.stateOf(596), EngineState.on);
    });

    test('result-fallback failure keeps last confirmed', () {
      tracker.seedConfirmed(10, EngineState.on);
      tracker.markCommandPending(10, 'engineStop');
      tracker.onPositionUpdate(
        deviceId: 10,
        attributes: {'result': 'S20,ERROR,1'},
        timestamp: DateTime(2026, 9, 22, 15),
      );
      expect(tracker.stateOf(10), EngineState.commandFailed);
      expect(tracker.lastConfirmedOf(10), EngineState.on);
      expect(tracker.pendingOf(10), isNull);
    });

    test('timeout / unconfirmed via monotonic deadline', () {
      tracker.markCommandPending(20, 'engineStop');
      expect(tracker.stateOf(20), EngineState.pending);

      // Advance monotonic clock past 30s without using wall DateTime.
      // Stopwatch can't be forced forward easily — use a pre-aged deadline
      // by constructing tracker with short timeout and sleeping briefly, OR
      // inject elapsed by using a custom approach: checkTimeouts after
      // manually setting via short timeout.
      final fast = EngineStateTracker(
        stopwatch: mono,
        pendingTimeout: const Duration(milliseconds: 1),
      );
      fast.markCommandPending(20, 'engineStop');
      // Ensure elapsed passes deadline.
      while (mono.elapsedMilliseconds <
          (fast.pendingOf(20)!.deadlineMonoMs)) {
        // busy wait tiny bit
      }
      expect(fast.checkTimeouts(), isTrue);
      expect(fast.stateOf(20), EngineState.unconfirmed);
      expect(fast.pendingOf(20), isNull);
    });

    test('out-of-order update rejection', () {
      final t1 = DateTime(2026, 9, 22, 10, 0, 0);
      final t0 = DateTime(2026, 9, 22, 9, 0, 0);

      tracker.onPositionUpdate(
        deviceId: 5,
        attributes: {'blocked': true},
        timestamp: t1,
      );
      expect(tracker.stateOf(5), EngineState.off);

      final applied = tracker.onPositionUpdate(
        deviceId: 5,
        attributes: {'blocked': false},
        timestamp: t0, // older
      );
      expect(applied, isFalse);
      expect(tracker.stateOf(5), EngineState.off);
    });

    test('concurrent commands on two devices do not interfere', () {
      tracker.markCommandPending(100, 'engineStop');
      tracker.markCommandPending(200, 'engineResume');

      tracker.onPositionUpdate(
        deviceId: 100,
        attributes: {'result': 'S20,OK,1'},
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
      expect(tracker.stateOf(100), EngineState.off);
    });

    test('null attributes do not throw', () {
      expect(
        () => tracker.onPositionUpdate(
          deviceId: 1,
          attributes: null,
          timestamp: DateTime.now(),
        ),
        returnsNormally,
      );
      expect(tracker.stateOf(1), EngineState.unknown);
    });

    test('offline while pending → unconfirmed', () {
      tracker.markCommandPending(7, 'engineStop');
      tracker.onDeviceStatus(deviceId: 7, status: 'offline');
      expect(tracker.stateOf(7), EngineState.unconfirmed);
      expect(tracker.pendingOf(7), isNull);
    });

    test('new pending command replaces old pending', () {
      tracker.markCommandPending(3, 'engineStop');
      tracker.markCommandPending(3, 'engineResume');
      expect(tracker.pendingOf(3)?.commandType, 'engineResume');

      tracker.onPositionUpdate(
        deviceId: 3,
        attributes: {'result': 'OK'},
        timestamp: DateTime(2026, 9, 22, 17),
      );
      expect(tracker.stateOf(3), EngineState.on);
    });
  });
}
