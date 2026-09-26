import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart' hide Response;
import '../../controllers/dashboard_controller/dashboard_controller.dart';
import '../../controllers/engine_state_controller/engine_state_controller.dart';
import '../../model/device_model/device_model.dart';
import '../../model/device_view_model/device_view_model.dart';
import '../../model/engine_state/engine_state.dart';
import '../../model/position_model/position_model.dart';
import '../../repositories/apis.dart';
import '../../repositories/network_client_repo.dart';
import '../../repositories/shared_pref_repo.dart';
import '../../services/traccar_socket_service.dart';
import '../../utills/common.dart';
import '../../utills/custom_snackbar.dart';
import '../../utills/logging.dart';
import '../../widgets/dialogs/confirm_action_dialog.dart';

class DeviceDetailController extends GetxController {
  DeviceDetailController({required this.deviceId, this.initial});

  final int deviceId;
  final DeviceViewModel? initial;

  final SharedPrefsRepository sharedPrefsRepository = SharedPrefsRepository();
  late final RequestClient _requestClient = RequestClient(
    sharedPrefsRepository: sharedPrefsRepository,
  );
  final TraccarSocketService _socketService = TraccarSocketService();
  EngineStateController get _engineStates => Get.find<EngineStateController>();

  final deviceView = Rxn<DeviceViewModel>();
  final isLoading = false.obs;
  final isCommandLoading = false.obs;
  final supportedCommands = <String>[].obs;
  /// Last successful command: `engineStop` | `engineResume` | null
  final lastEngineCommand = Rxn<String>();

  StreamSubscription<TraccarSocketPayload>? _socketSub;
  Timer? _pollTimer;

  @override
  void onInit() {
    super.onInit();
    final seed = initial;
    if (seed != null) {
      deviceView.value = seed.copyWith(
        lastEngineCommand: sharedPrefsRepository.getEngineCommand(deviceId) ??
            seed.lastEngineCommand,
      );
    }
    lastEngineCommand.value =
        sharedPrefsRepository.getEngineCommand(deviceId) ??
            seed?.lastEngineCommand;
    loadDevice();
    _startLiveUpdates();
  }

  /// True when engine is treated as stopped (show Resume button).
  bool get isEngineStopped {
    // Live blocked wins.
    final blocked =
        DeviceModel.blockedFrom(deviceView.value?.position?.attributes);
    if (blocked == true) return true;
    if (blocked == false) return false;

    final engine = _engineStates;
    final state = engine.stateOf(deviceId);
    switch (state) {
      case EngineState.off:
        return true;
      case EngineState.on:
        return false;
      case EngineState.pending:
        return engine.tracker.pendingOf(deviceId)?.commandType == 'engineStop';
      case EngineState.commandFailed:
      case EngineState.unconfirmed:
        return engine.lastConfirmedOf(deviceId) == EngineState.off;
      case EngineState.unknown:
      case EngineState.noRelayData:
        final cmd = lastEngineCommand.value ??
            sharedPrefsRepository.getEngineCommand(deviceId);
        if (cmd == 'engineStop') return true;
        if (cmd == 'engineResume') return false;
        return sharedPrefsRepository.getEngineBlockedState(deviceId) == 'off';
    }
  }

  void _ingestPosition(PositionModel position) {
    _engineStates.onPositionUpdate(
      deviceId: deviceId,
      attributes: position.attributes,
      deviceTime: position.deviceTime,
      fixTime: position.fixTime,
      serverTime: position.serverTime,
      protocol: position.protocol,
    );
  }

  void _ingestInitialFromRest({
    required PositionModel? position,
    required DeviceModel device,
  }) {
    _engineStates.applyDeviceRestSnapshot(
      deviceId: deviceId,
      positionAttributes: position?.attributes,
      deviceAttributes: device.attributes,
      timestamp: position?.deviceTime ??
          position?.fixTime ??
          position?.serverTime,
      protocol: position?.protocol,
    );
    // Ignore future — fire history backfill for real blocked/RELAY data.
    _engineStates.refreshDeviceFromTraccar(deviceId);
  }

  Future<void> loadDevice({bool showLoader = true}) async {
    try {
      if (showLoader) isLoading.value = true;

      final responses = await Future.wait([
        _requestClient.request<Response>(
          url: AppUrl.devices,
          method: RequestType.get,
          queryParameters: {'id': deviceId},
        ),
        _requestClient.request<Response>(
          url: AppUrl.positions,
          method: RequestType.get,
          queryParameters: {'deviceId': deviceId},
        ),
        _requestClient.request<Response>(
          url: AppUrl.commandsTypes,
          method: RequestType.get,
          queryParameters: {'deviceId': deviceId},
        ),
      ]);

      final devices = _asMapList(responses[0].data);
      final positions = _asMapList(responses[1].data);
      final commands = _asMapList(responses[2].data);

      if (devices.isEmpty) {
        throw Exception('Device not found');
      }

      final device = DeviceModel.fromJson(devices.first);
      final position =
          positions.isNotEmpty ? PositionModel.fromJson(positions.first) : null;

      _ingestInitialFromRest(position: position, device: device);

      deviceView.value = DeviceViewModel(
        device: device,
        position: position,
        lastEngineCommand: lastEngineCommand.value ??
            sharedPrefsRepository.getEngineCommand(deviceId),
      );
      supportedCommands.value = commands
          .map((c) => c['type']?.toString() ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      Logger.error(e.toString());
      if (Get.context != null) {
        Common.showDioErrorDialog(Get.context!, e: e);
      }
    } catch (e) {
      Logger.error(e.toString());
      snackBarCustom(
        title: 'Error',
        message: e.toString(),
        type: SnackBarType.error,
      );
    } finally {
      isLoading.value = false;
    }
  }

  void _startLiveUpdates() {
    _socketService.connect();
    _socketSub = _socketService.stream.listen(_onSocketPayload);
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      loadDevice(showLoader: false);
    });
  }

  void _onSocketPayload(TraccarSocketPayload payload) {
    final current = deviceView.value;
    if (current == null) return;

    DeviceViewModel updated = current;

    for (final raw in payload.devices) {
      if (raw['id'] == deviceId) {
        updated = updated.copyWith(device: DeviceModel.fromJson(raw));
        _engineStates.onDeviceStatus(
          deviceId: deviceId,
          status: raw['status']?.toString(),
        );
      }
    }

    for (final raw in payload.positions) {
      if (raw['deviceId'] == deviceId) {
        final attrs = raw['attributes'];
        print('========== POSITION UPDATE (device $deviceId) ==========');
        print('attributes: $attrs');
        if (attrs is Map) {
          print('ignition: ${attrs['ignition']}');
          print('blocked: ${attrs['blocked']}');
          print('motion: ${attrs['motion']}');
          print('result: ${attrs['result']}');
        }
        print('=======================================================');
        final position = PositionModel.fromJson(raw);
        _ingestPosition(position);
        updated = updated.copyWith(position: position);
      }
    }

    for (final raw in payload.events) {
      if (raw['deviceId'] == deviceId) {
        print('========== EVENT (device $deviceId) ==========');
        print('type: ${raw['type']}');
        print('event: $raw');
        print('attributes: ${raw['attributes']}');
        print('===========================================');
      }
    }

    deviceView.value = updated;
  }

  Future<void> stopEngine(BuildContext context) async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: 'Stop Engine?',
      message:
          'This will send an engine stop command to ${deviceView.value?.name ?? 'this device'}. The vehicle will not be able to start until resumed.',
      confirmLabel: 'Stop Engine',
      isDestructive: true,
      icon: Icons.block_rounded,
    );
    if (!confirmed || !context.mounted) return;
    await _sendCommand(
      context,
      'engineStop',
      successMessage: 'Engine stop command sent',
    );
  }

  Future<void> resumeEngine(BuildContext context) async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: 'Resume Engine?',
      message:
          'This will send an engine resume command to ${deviceView.value?.name ?? 'this device'} and allow the vehicle to start again.',
      confirmLabel: 'Resume',
      isDestructive: false,
      icon: Icons.play_arrow_rounded,
    );
    if (!confirmed || !context.mounted) return;
    await _sendCommand(
      context,
      'engineResume',
      successMessage: 'Engine resume command sent',
    );
  }

  Future<void> _sendCommand(
    BuildContext context,
    String type, {
    required String successMessage,
  }) async {
    try {
      isCommandLoading.value = true;
      EasyLoading.show(status: 'Sending command...');

      // Optimistic pending *before* HTTP resolves.
      _engineStates.markCommandPending(deviceId, type);

      final requestBody = <String, dynamic>{
        'deviceId': deviceId,
        'type': type,
        'attributes': <String, dynamic>{},
      };

      // Traccar may return 200/202 with an empty body; default JSON decode
      // then throws FormatException → DioExceptionType.unknown / status null.
      final response = await _requestClient.request<Response>(
        url: AppUrl.commandsSend,
        method: RequestType.post,
        body: requestBody,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (code) => code != null && code >= 200 && code < 300,
        ),
      );

      final raw = response.data;
      dynamic data = raw;
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          data = jsonDecode(raw);
        } catch (_) {
          data = raw;
        }
      } else if (raw is String && raw.trim().isEmpty) {
        data = null;
      }

      print('========== ENGINE COMMAND — EXACT RESPONSE ==========');
      print('REQUEST');
      print('  POST ${AppUrl.commandsSend}');
      print('  body: $requestBody');
      print('RESPONSE');
      print('  status: ${response.statusCode} ${response.statusMessage}');
      print('  headers: ${response.headers.map}');
      print('  exact body (raw): $raw');
      print('  exact body (type): ${raw.runtimeType}');
      print('  exact body (parsed): $data');
      print('=====================================================');
      Logger.success(
        'Engine $type exact response [${response.statusCode}]: $raw',
      );

      lastEngineCommand.value = type;
      await sharedPrefsRepository.setEngineCommand(deviceId, type);
      // If live blocked is null, apply ON/OFF locally and persist prefs.
      // When blocked arrives later it overwrites via onPositionUpdate.
      final liveBlocked =
          DeviceModel.blockedFrom(deviceView.value?.position?.attributes);
      if (liveBlocked == null) {
        _engineStates.applyCommandLocallyUntilBlocked(deviceId, type);
      } else {
        // blocked already present — still sync command prefs; state from blocked.
        await sharedPrefsRepository.setEngineBlockedState(
          deviceId,
          liveBlocked ? 'off' : 'on',
        );
        await sharedPrefsRepository.setDeviceReportsBlocked(deviceId, true);
      }

      final current = deviceView.value;
      if (current != null) {
        deviceView.value = current.copyWith(lastEngineCommand: type);
      }
      _syncDashboardEngineCommand(type);

      snackBarCustom(
        title: 'Command Sent',
        message: successMessage,
        type: SnackBarType.success,
      );

      Future.delayed(const Duration(seconds: 2), () {
        loadDevice(showLoader: false);
      });
    } on DioException catch (e) {
      _engineStates.failCommandSend(deviceId);
      final exact = e.response?.data;
      print('========== ENGINE COMMAND — EXACT RESPONSE (ERROR) ==========');
      print('REQUEST');
      print('  POST ${AppUrl.commandsSend}');
      print('  body: {deviceId: $deviceId, type: $type, attributes: {}}');
      print('RESPONSE');
      print('  status: ${e.response?.statusCode} ${e.response?.statusMessage}');
      print('  headers: ${e.response?.headers.map}');
      print('  exact body (raw): $exact');
      print('  exact body (type): ${exact.runtimeType}');
      print('  dioType: ${e.type}');
      print('==============================================================');
      Logger.error(
        'Engine $type exact response [${e.response?.statusCode}]: $exact',
      );
      if (context.mounted) {
        Common.showDioErrorDialog(context, e: e);
      }
    } catch (e) {
      _engineStates.failCommandSend(deviceId);
      print('========== ENGINE COMMAND — EXACT RESPONSE (ERROR) ==========');
      print('command: $type');
      print('exact error: $e');
      print('==============================================================');
      snackBarCustom(
        title: 'Error',
        message: e.toString(),
        type: SnackBarType.error,
      );
    } finally {
      isCommandLoading.value = false;
      EasyLoading.dismiss();
    }
  }

  void _syncDashboardEngineCommand(String type) {
    if (!Get.isRegistered<DashboardController>()) return;
    final dash = Get.find<DashboardController>();
    final index = dash.devices.indexWhere((d) => d.id == deviceId);
    if (index < 0) return;
    dash.devices[index] =
        dash.devices[index].copyWith(lastEngineCommand: type);
    dash.devices.refresh();
  }

  List<Map<String, dynamic>> _asMapList(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  void onClose() {
    _socketSub?.cancel();
    _pollTimer?.cancel();
    _socketService.dispose();
    super.onClose();
  }
}
