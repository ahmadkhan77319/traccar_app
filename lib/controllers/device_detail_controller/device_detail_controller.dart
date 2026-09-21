import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart' hide Response;
import '../../controllers/dashboard_controller/dashboard_controller.dart';
import '../../model/device_model/device_model.dart';
import '../../model/device_view_model/device_view_model.dart';
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
  bool get isEngineStopped =>
      deviceView.value?.isEngineStopped ??
      lastEngineCommand.value == 'engineStop';

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
        }
        print('=======================================================');
        updated = updated.copyWith(position: PositionModel.fromJson(raw));
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

      final response = await _requestClient.request<Response>(
        url: AppUrl.commandsSend,
        method: RequestType.post,
        body: {
          'deviceId': deviceId,
          'type': type,
          'attributes': <String, dynamic>{},
        },
      );

      final data = response.data;
      print('========== ENGINE COMMAND RESPONSE ==========');
      print('HTTP status: ${response.statusCode} ${response.statusMessage}');
      print('meaning: command ACCEPTED by Traccar (not device confirmed)');
      if (data is Map) {
        print('id: ${data['id']}');
        print('deviceId: ${data['deviceId']}');
        print('type: ${data['type']}');
        print('textChannel: ${data['textChannel']}');
        print('attributes: ${data['attributes']}');
        print('full data: $data');
      } else {
        print('data: $data');
      }
      print('=============================================');
      Logger.success(
        'Engine $type response [${response.statusCode}]: $data',
      );

      lastEngineCommand.value = type;
      await sharedPrefsRepository.setEngineCommand(deviceId, type);

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
      print('========== ENGINE COMMAND ERROR ==========');
      print('command: $type');
      print('deviceId: $deviceId');
      print('statusCode: ${e.response?.statusCode}');
      print('response data: ${e.response?.data}');
      print('error: ${e.message}');
      print('==========================================');
      Logger.error(
        'Engine $type failed [${e.response?.statusCode}]: ${e.response?.data}',
      );
      if (context.mounted) {
        Common.showDioErrorDialog(context, e: e);
      }
    } catch (e) {
      print('========== ENGINE COMMAND ERROR ==========');
      print('command: $type');
      print('error: $e');
      print('==========================================');
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
