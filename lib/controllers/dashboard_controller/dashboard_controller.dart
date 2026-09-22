import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import '../../controllers/engine_state_controller/engine_state_controller.dart';
import '../../model/device_model/device_model.dart';
import '../../model/device_view_model/device_view_model.dart';
import '../../model/position_model/position_model.dart';
import '../../repositories/apis.dart';
import '../../repositories/network_client_repo.dart';
import '../../repositories/shared_pref_repo.dart';
import '../../services/traccar_socket_service.dart';
import '../../utills/common.dart';
import '../../utills/logging.dart';

class DashboardController extends GetxController {
  final SharedPrefsRepository sharedPrefsRepository = SharedPrefsRepository();
  late final RequestClient _requestClient = RequestClient(
    sharedPrefsRepository: sharedPrefsRepository,
  );
  final TraccarSocketService _socketService = TraccarSocketService();
  EngineStateController get _engineStates => Get.find<EngineStateController>();

  final devices = <DeviceViewModel>[].obs;
  final isLoading = false.obs;
  final isRefreshing = false.obs;
  final searchQuery = ''.obs;
  final selectedFilter = 'all'.obs;
  final searchController = TextEditingController();

  StreamSubscription<TraccarSocketPayload>? _socketSub;
  Timer? _pollTimer;

  int get totalCount => devices.length;
  int get onlineCount =>
      devices.where((d) => d.device.status?.toLowerCase() == 'online').length;
  int get offlineCount =>
      devices.where((d) => d.device.status?.toLowerCase() == 'offline').length;
  int get movingCount =>
      devices.where((d) => d.state == DeviceState.moving).length;
  int get idleCount => devices.where((d) => d.state == DeviceState.idle).length;

  /// Filters based on Traccar connection status + live activity.
  static const List<Map<String, String>> statusFilters = [
    {'key': 'all', 'label': 'All'},
    {'key': 'online', 'label': 'Online'},
    {'key': 'offline', 'label': 'Offline'},
    {'key': 'moving', 'label': 'Moving'},
    {'key': 'idle', 'label': 'Idle'},
  ];

  List<DeviceViewModel> get filteredDevices {
    var list = devices.toList();
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where((d) =>
              d.name.toLowerCase().contains(query) ||
              d.uniqueId.toLowerCase().contains(query) ||
              d.address.toLowerCase().contains(query))
          .toList();
    }

    switch (selectedFilter.value) {
      case 'online':
        list = list
            .where((d) => d.device.status?.toLowerCase() == 'online')
            .toList();
        break;
      case 'offline':
        list = list
            .where((d) => d.device.status?.toLowerCase() == 'offline')
            .toList();
        break;
      case 'moving':
        list = list.where((d) => d.state == DeviceState.moving).toList();
        break;
      case 'idle':
        list = list.where((d) => d.state == DeviceState.idle).toList();
        break;
    }

    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  void onInit() {
    super.onInit();
    fetchDashboard();
    _startLiveUpdates();
  }

  Future<void> fetchDashboard({bool showLoader = true}) async {
    try {
      if (showLoader) {
        isLoading.value = true;
      } else {
        isRefreshing.value = true;
      }

      final responses = await Future.wait([
        _requestClient.request<Response>(
          url: AppUrl.devices,
          method: RequestType.get,
        ),
        _requestClient.request<Response>(
          url: AppUrl.positions,
          method: RequestType.get,
        ),
      ]);

      final deviceList = _asMapList(responses[0].data)
          .map(DeviceModel.fromJson)
          .toList();
      final positionList = _asMapList(responses[1].data)
          .map(PositionModel.fromJson)
          .toList();

      final positionsByDevice = <int, PositionModel>{
        for (final p in positionList)
          if (p.deviceId != null) p.deviceId!: p,
      };

      devices.value = deviceList
          .map(
            (device) => DeviceViewModel(
              device: device,
              position: positionsByDevice[device.id],
              lastEngineCommand:
                  sharedPrefsRepository.getEngineCommand(device.id ?? 0),
            ),
          )
          .toList();

      for (final entry in positionsByDevice.entries) {
        final p = entry.value;
        _engineStates.onPositionUpdate(
          deviceId: entry.key,
          attributes: p.attributes,
          deviceTime: p.deviceTime,
          fixTime: p.fixTime,
          serverTime: p.serverTime,
        );
      }

      Logger.success('Loaded ${devices.length} devices');
    } on DioException catch (e) {
      Logger.error(e.toString());
      if (Get.context != null) {
        Common.showDioErrorDialog(Get.context!, e: e);
      }
    } catch (e) {
      Logger.error(e.toString());
    } finally {
      isLoading.value = false;
      isRefreshing.value = false;
    }
  }

  void _startLiveUpdates() {
    _socketService.connect();
    _socketSub = _socketService.stream.listen(_onSocketPayload);

    // Fallback poll every 30s in case WS is unavailable
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      fetchDashboard(showLoader: false);
    });
  }

  void _onSocketPayload(TraccarSocketPayload payload) {
    if (payload.devices.isEmpty && payload.positions.isEmpty) return;

    final current = Map<int, DeviceViewModel>.fromEntries(
      devices.map((d) => MapEntry(d.id, d)),
    );

    for (final raw in payload.devices) {
      final updated = DeviceModel.fromJson(raw);
      final id = updated.id;
      if (id == null) continue;
      _engineStates.onDeviceStatus(
        deviceId: id,
        status: updated.status,
      );
      final existing = current[id];
      if (existing != null) {
        current[id] = existing.copyWith(device: updated);
      } else {
        current[id] = DeviceViewModel(
          device: updated,
          lastEngineCommand: sharedPrefsRepository.getEngineCommand(id),
        );
      }
    }

    for (final raw in payload.positions) {
      final updated = PositionModel.fromJson(raw);
      final id = updated.deviceId;
      if (id == null) continue;
      _engineStates.onPositionUpdate(
        deviceId: id,
        attributes: updated.attributes,
        deviceTime: updated.deviceTime,
        fixTime: updated.fixTime,
        serverTime: updated.serverTime,
      );
      final existing = current[id];
      if (existing != null) {
        current[id] = existing.copyWith(position: updated);
      }
    }

    devices.value = current.values.toList();
  }

  void onSearchChanged(String value) {
    searchQuery.value = value;
  }

  void setFilter(String filter) {
    selectedFilter.value = filter;
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
    searchController.dispose();
    super.onClose();
  }
}
