import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart' hide Response;

import '../../model/device_model/device_model.dart';
import '../../model/engine_state/engine_state.dart';
import '../../model/position_model/position_model.dart';
import '../../repositories/apis.dart';
import '../../repositories/network_client_repo.dart';
import '../../repositories/shared_pref_repo.dart';
import '../../utills/logging.dart';
import 'engine_state_tracker.dart';

/// Live-only engine state from Traccar REST + WebSocket (no disk cache).
class EngineStateController extends GetxController with WidgetsBindingObserver {
  EngineStateController({
    SharedPrefsRepository? prefs,
    RequestClient? requestClient,
    EngineStateTracker? tracker,
  })  : _prefs = prefs ?? SharedPrefsRepository(),
        tracker = tracker ?? EngineStateTracker() {
    _requestClient =
        requestClient ?? RequestClient(sharedPrefsRepository: _prefs);
  }

  final SharedPrefsRepository _prefs;
  late final RequestClient _requestClient;
  final EngineStateTracker tracker;

  final Map<int, Rx<EngineState>> _rxStates = {};
  final revision = 0.obs;
  final isRefreshing = false.obs;

  Timer? _deadlinePoll;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
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

  Rx<EngineState> engineStateFor(int deviceId) {
    return _rxStates.putIfAbsent(
      deviceId,
      () => tracker.stateOf(deviceId).obs,
    );
  }

  EngineState stateOf(int deviceId) => tracker.stateOf(deviceId);

  EngineState? lastConfirmedOf(int deviceId) =>
      tracker.lastConfirmedOf(deviceId);

  /// Show engine status / Stop-Resume only when Traccar reports `blocked`.
  bool reportsBlocked(int deviceId) => tracker.reportsBlocked(deviceId);

  /// Same check, also trusting position attrs, ct3 protocol, or cached blocked.
  bool showsEngineUi(
    int deviceId, {
    Map<String, dynamic>? positionAttributes,
    String? protocol,
  }) {
    if (tracker.reportsBlocked(deviceId)) return true;
    if (_prefs.deviceReportsBlocked(deviceId)) return true;
    if (positionAttributes?['blocked'] != null) return true;
    // ct3 always has immobilizer support — show while waiting for blocked.
    final proto = (protocol ?? '').toLowerCase();
    if (proto == 'ct3') return true;
    return false;
  }

  void _seedFromPrefs(int deviceId) {
    // Command first — when blocked is null we show what the user last sent.
    final cmd = _prefs.getEngineCommand(deviceId);
    if (cmd == 'engineStop' || cmd == 'engineResume') {
      tracker.seedCommandFromCache(deviceId, cmd);
    }
    if (!_prefs.deviceReportsBlocked(deviceId)) return;
    final raw = _prefs.getEngineBlockedState(deviceId);
    EngineState? state;
    if (raw == 'on') state = EngineState.on;
    if (raw == 'off') state = EngineState.off;
    tracker.seedBlockedFromCache(
      deviceId,
      reportsBlocked: true,
      state: state,
    );
  }

  /// Persist ON/OFF for cards after restart / when blocked is omitted.
  void _persistDisplayState(int deviceId) {
    final state = tracker.stateOf(deviceId);
    if (state != EngineState.on && state != EngineState.off) return;
    _prefs.setEngineBlockedState(
      deviceId,
      state == EngineState.on ? 'on' : 'off',
    );
    if (tracker.reportsBlocked(deviceId)) {
      _prefs.setDeviceReportsBlocked(deviceId, true);
    }
    // Keep command prefs aligned with last known display status.
    _prefs.setEngineCommand(
      deviceId,
      state == EngineState.off ? 'engineStop' : 'engineResume',
    );
  }

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
        // ct3: friendly first paint until snapshot resolves to ON.
        if (tracker.isCt3(deviceId)) return 'Engine ON';
        return 'Checking engine status…';
      case EngineState.noRelayData:
        return 'No relay data available';
    }
  }

  void markCommandPending(int deviceId, String commandType) {
    tracker.markCommandPending(deviceId, commandType);
    _syncRx(deviceId);
  }

  /// After Traccar accepts Stop/Resume — apply ON/OFF when blocked is absent
  /// (ct1 always; ct3 until the next real `blocked` packet).
  void confirmLocalCommandIfIgnitionMode(int deviceId, String commandType) {
    if (tracker.confirmLocalCommand(deviceId, commandType)) {
      _persistDisplayState(deviceId);
      _syncRx(deviceId);
    }
  }

  void onPositionUpdate({
    required int deviceId,
    Map<String, dynamic>? attributes,
    DateTime? deviceTime,
    DateTime? fixTime,
    DateTime? serverTime,
    String? protocol,
  }) {
    final ts = deviceTime ?? fixTime ?? serverTime;
    final changed = tracker.onPositionUpdate(
      deviceId: deviceId,
      attributes: attributes,
      timestamp: ts,
      protocol: protocol,
      lastEngineCommand: _prefs.getEngineCommand(deviceId),
    );
    // Always refresh UI when blocked is present so card/sheet update immediately.
    final hasBlocked = attributes != null &&
        attributes.containsKey('blocked') &&
        attributes['blocked'] != null;
    if (changed || hasBlocked) {
      _persistDisplayState(deviceId);
      _syncRx(deviceId);
      revision.value++;
    }
  }

  void onDeviceStatus({required int deviceId, String? status}) {
    final changed = tracker.onDeviceStatus(deviceId: deviceId, status: status);
    if (changed) _syncRx(deviceId);
  }

  /// Apply REST snapshot for one device (detail load). No local cache.
  void applyDeviceRestSnapshot({
    required int deviceId,
    Map<String, dynamic>? positionAttributes,
    Map<String, dynamic>? deviceAttributes,
    DateTime? timestamp,
    String? protocol,
  }) {
    _seedFromPrefs(deviceId);
    final changed = tracker.applyInitialSnapshot(
      deviceId: deviceId,
      positionAttributes: positionAttributes,
      deviceAttributes: deviceAttributes,
      timestamp: timestamp,
      protocol: protocol,
      lastEngineCommand: _prefs.getEngineCommand(deviceId),
    );
    if (changed) {
      _persistDisplayState(deviceId);
      _syncRx(deviceId);
    } else {
      _syncRx(deviceId, bump: false);
      revision.value++;
    }
  }

  /// Apply already-fetched positions (dashboard batch) — no local storage.
  void applyPositionsFromRest(
    Iterable<PositionModel> positions, {
    Map<int, DeviceModel>? devicesById,
  }) {
    for (final p in positions) {
      final id = p.deviceId;
      if (id == null) continue;
      _seedFromPrefs(id);
      final device = devicesById?[id];
      print(
        '========== ENGINE REST latest (device $id) ==========\n'
        'protocol: ${p.protocol}\n'
        'attributes: ${p.attributes}\n'
        'blocked: ${p.attributes?['blocked']} result: ${p.attributes?['result']}\n'
        '====================================================',
      );
      final changed = tracker.applyInitialSnapshot(
        deviceId: id,
        positionAttributes: p.attributes,
        deviceAttributes: device?.attributes,
        timestamp: p.deviceTime ?? p.fixTime ?? p.serverTime,
        protocol: p.protocol,
        lastEngineCommand: _prefs.getEngineCommand(id),
      );
      if (changed) _syncRx(id, bump: false);
      _persistDisplayState(id);
    }
    revision.value++;
  }

  /// For devices still unknown after latest positions, query Traccar history.
  /// Also refresh ct3 units whose latest packet omitted `blocked`.
  Future<void> backfillUnknownFromHistory(
    List<int> deviceIds, {
    Map<int, String?> protocolsByDevice = const {},
  }) async {
    final stillUnknown = deviceIds.where((id) {
      if (stateOf(id) == EngineState.unknown) return true;
      // ct3: latest may omit blocked — keep scanning until we have it this session
      final proto = (protocolsByDevice[id] ?? '').toLowerCase();
      if (proto == 'ct3' && !tracker.reportsBlocked(id)) return true;
      return false;
    }).toList();
    if (stillUnknown.isEmpty) {
      print('ENGINE HYDRATE: all devices resolved from latest /api/positions');
      return;
    }
    print(
      'ENGINE HYDRATE: ${stillUnknown.length} unknown → '
      'GET /api/positions?from&to (last 24h)',
    );
    await _backfillFromHistory(stillUnknown);
  }

  /// Fetch latest positions, then for devices still unknown pull recent
  /// history from Traccar and find the newest `blocked` / `RELAY` result.
  Future<void> hydrateEngineStatesFromTraccar({
    List<int>? deviceIds,
  }) async {
    try {
      isRefreshing.value = true;
      print('========== ENGINE HYDRATE: GET /api/positions (+ devices) ==========');

      final responses = await Future.wait([
        _requestClient.request<Response>(
          url: AppUrl.positions,
          method: RequestType.get,
        ),
        _requestClient.request<Response>(
          url: AppUrl.devices,
          method: RequestType.get,
        ),
      ]);

      final positions = _asMapList(responses[0].data)
          .map(PositionModel.fromJson)
          .toList();
      final devices = _asMapList(responses[1].data)
          .map(DeviceModel.fromJson)
          .toList();
      final byId = <int, DeviceModel>{
        for (final d in devices)
          if (d.id != null) d.id!: d,
      };

      applyPositionsFromRest(positions, devicesById: byId);

      final ids = deviceIds ??
          [
            ...byId.keys,
            ...positions.map((p) => p.deviceId).whereType<int>(),
          ].toSet().toList();

      await backfillUnknownFromHistory(
        ids,
        protocolsByDevice: {
          for (final p in positions)
            if (p.deviceId != null) p.deviceId!: p.protocol,
        },
      );
    } catch (e) {
      Logger.error('Engine hydrate failed: $e');
    } finally {
      isRefreshing.value = false;
    }
  }

  Future<void> _backfillFromHistory(List<int> deviceIds) async {
    final to = DateTime.now().toUtc();
    final from = to.subtract(const Duration(hours: 24));
    final fromIso = from.toIso8601String().replaceFirst(RegExp(r'\.\d+'), '');
    final toIso = to.toIso8601String().replaceFirst(RegExp(r'\.\d+'), '');

    // One history call for the account window, then filter by device.
    try {
      final response = await _requestClient.request<Response>(
        url: AppUrl.positions,
        method: RequestType.get,
        queryParameters: {
          'from': fromIso.endsWith('Z') ? fromIso : '${fromIso}Z',
          'to': toIso.endsWith('Z') ? toIso : '${toIso}Z',
        },
      );

      final all = _asMapList(response.data).map(PositionModel.fromJson).toList();
      final byDevice = <int, List<PositionModel>>{};
      for (final p in all) {
        final id = p.deviceId;
        if (id == null || !deviceIds.contains(id)) continue;
        byDevice.putIfAbsent(id, () => []).add(p);
      }

      for (final id in deviceIds) {
        final list = byDevice[id] ?? const <PositionModel>[];
        list.sort((a, b) {
          final ta = a.deviceTime ?? a.fixTime ?? a.serverTime;
          final tb = b.deviceTime ?? b.fixTime ?? b.serverTime;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta); // newest first
        });

        print(
          'ENGINE HYDRATE history device $id: ${list.length} positions, '
          'scanning for blocked/RELAY…',
        );

        final changed = tracker.applyHistoryNewestFirst(
          deviceId: id,
          positionsNewestFirst: list
              .map(
                (p) => (
                  attributes: p.attributes,
                  timestamp: p.deviceTime ?? p.fixTime ?? p.serverTime,
                ),
              )
              .toList(),
        );
        if (changed) {
          print(
            'ENGINE HYDRATE device $id → ${stateOf(id)} '
            '(from history attributes)',
          );
          _persistDisplayState(id);
          _syncRx(id, bump: false);
        } else if (list.isNotEmpty) {
          // No blocked/RELAY — drive ON/OFF from ignition locally (ct1).
          final newest = list.first.attributes;
          final applied = tracker.enableIgnitionFallback(
            id,
            attributes: newest,
            lastEngineCommand: _prefs.getEngineCommand(id),
          );
          print(
            'ENGINE HYDRATE device $id → ${stateOf(id)} '
            '(ignition fallback, no blocked/RELAY)',
          );
          if (applied) _syncRx(id, bump: false);
          else _syncRx(id, bump: false);
        }
      }
      revision.value++;
    } catch (e) {
      Logger.error('Engine history backfill failed: $e');
      // Fallback: per-device queries
      for (final id in deviceIds) {
        if (stateOf(id) != EngineState.unknown) continue;
        try {
          final response = await _requestClient.request<Response>(
            url: AppUrl.positions,
            method: RequestType.get,
            queryParameters: {
              'deviceId': id,
              'from': fromIso.endsWith('Z') ? fromIso : '${fromIso}Z',
              'to': toIso.endsWith('Z') ? toIso : '${toIso}Z',
            },
          );
          final list = _asMapList(response.data)
              .map(PositionModel.fromJson)
              .toList()
            ..sort((a, b) {
              final ta = a.deviceTime ?? a.fixTime ?? a.serverTime;
              final tb = b.deviceTime ?? b.fixTime ?? b.serverTime;
              if (ta == null || tb == null) return 0;
              return tb.compareTo(ta);
            });
          final changed = tracker.applyHistoryNewestFirst(
            deviceId: id,
            positionsNewestFirst: list
                .map(
                  (p) => (
                    attributes: p.attributes,
                    timestamp: p.deviceTime ?? p.fixTime ?? p.serverTime,
                  ),
                )
                .toList(),
          );
          if (changed) {
            _syncRx(id, bump: false);
          } else if (list.isNotEmpty) {
            tracker.enableIgnitionFallback(
              id,
              attributes: list.first.attributes,
              lastEngineCommand: _prefs.getEngineCommand(id),
            );
            _syncRx(id, bump: false);
          }
        } catch (e2) {
          Logger.error('Engine history for $id failed: $e2');
        }
      }
      revision.value++;
    }
  }

  /// Fresh REST pull for one device (detail screen) + 24h history if needed.
  Future<void> refreshDeviceFromTraccar(int deviceId) async {
    try {
      isRefreshing.value = true;
      print('========== ENGINE REFRESH device $deviceId ==========');
      final responses = await Future.wait([
        _requestClient.request<Response>(
          url: AppUrl.positions,
          method: RequestType.get,
          queryParameters: {'deviceId': deviceId},
        ),
        _requestClient.request<Response>(
          url: AppUrl.devices,
          method: RequestType.get,
          queryParameters: {'id': deviceId},
        ),
      ]);

      final positions = _asMapList(responses[0].data)
          .map(PositionModel.fromJson)
          .toList();
      final devices = _asMapList(responses[1].data)
          .map(DeviceModel.fromJson)
          .toList();

      final position = positions.isNotEmpty ? positions.first : null;
      final device = devices.isNotEmpty ? devices.first : null;

      print(
        'latest attributes: ${position?.attributes}\n'
        'blocked: ${position?.attributes?['blocked']} '
        'result: ${position?.attributes?['result']}',
      );

      final changed = tracker.applyInitialSnapshot(
        deviceId: deviceId,
        positionAttributes: position?.attributes,
        deviceAttributes: device?.attributes,
        timestamp: position?.deviceTime ??
            position?.fixTime ??
            position?.serverTime,
        protocol: position?.protocol,
        lastEngineCommand: _prefs.getEngineCommand(deviceId),
      );
      if (changed) {
        _persistDisplayState(deviceId);
        _syncRx(deviceId);
        revision.value++;
      }

      if (stateOf(deviceId) == EngineState.unknown) {
        await _backfillFromHistory([deviceId]);
      }
    } catch (e) {
      Logger.error('EngineState REST refresh failed for $deviceId: $e');
      if (tracker.stateOf(deviceId) == EngineState.unknown) {
        _syncRx(deviceId);
      }
    } finally {
      isRefreshing.value = false;
    }
  }

  /// Batch REST pull for account device list (one /api/positions call).
  Future<void> refreshAllFromTraccar() async {
    await hydrateEngineStatesFromTraccar();
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

  List<Map<String, dynamic>> _asMapList(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
