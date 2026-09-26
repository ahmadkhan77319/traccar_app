import '../device_model/device_model.dart';
import '../position_model/position_model.dart';

enum DeviceState { online, offline, moving, idle, unknown }

class DeviceViewModel {
  final DeviceModel device;
  final PositionModel? position;
  /// Last successful engine command for this device (`engineStop` / `engineResume`).
  final String? lastEngineCommand;

  const DeviceViewModel({
    required this.device,
    this.position,
    this.lastEngineCommand,
  });

  int get id => device.id ?? 0;
  String get name => device.name?.isNotEmpty == true
      ? device.name!
      : 'Device ${device.id ?? ''}';
  String get uniqueId => device.uniqueId ?? '—';
  String get address =>
      (position?.address?.isNotEmpty == true)
          ? position!.address!
          : 'Address unavailable';
  double get speedKph => position?.speedKph ?? 0;
  DateTime? get lastUpdate =>
      device.lastUpdate ?? position?.fixTime ?? position?.deviceTime;
  bool? get ignition => position?.ignition;
  /// True only when ignition was present and successfully parsed.
  bool get hasIgnitionReport => ignition != null;
  bool? get engineOn => position?.engineOn;

  /// Device supports immobilizer — from `GET /api/devices` attributes.
  bool get engineKillCapable => device.engineKillCapable;

  /// Live `blocked` from latest position (`true` = Engine OFF).
  bool? get blocked => DeviceModel.blockedFrom(position?.attributes);

  /// Display status: last stop/resume command updates UI immediately;
  /// otherwise uses latest position `attributes.ignition`.
  String get engineStatusLabel {
    if (lastEngineCommand == 'engineStop') return 'Engine OFF';
    if (lastEngineCommand == 'engineResume') return 'Engine ON';
    final ign = ignition;
    if (ign == null) return 'Engine Status Unknown';
    return ign ? 'Engine ON' : 'Engine OFF';
  }

  /// Same source of truth as [engineStatusLabel] for Idle / engine UI.
  bool get isEngineConsideredOn {
    if (lastEngineCommand == 'engineStop') return false;
    if (lastEngineCommand == 'engineResume') return true;
    return ignition == true;
  }

  /// True when UI should treat engine as stopped (show Resume).
  bool get isEngineStopped {
    if (lastEngineCommand == 'engineStop') return true;
    if (lastEngineCommand == 'engineResume') return false;
    if (ignition != null) return ignition == false;
    return false;
  }

  bool get hasLocation => position?.hasLocation == true;
  double? get latitude => position?.latitude;
  double? get longitude => position?.longitude;
  double get course => position?.course ?? 0;

  DeviceState get state {
    final status = (device.status ?? '').toLowerCase();

    // Traccar connection status: online | offline | unknown
    if (status == 'offline') return DeviceState.offline;
    if (status == 'unknown') return DeviceState.unknown;

    final isMoving = position?.motion == true || speedKph > 3;

    // Online (or missing status with a recent position)
    if (status == 'online' || status.isEmpty) {
      if (status.isEmpty && position == null && device.lastUpdate == null) {
        return DeviceState.offline;
      }
      // Moving takes priority
      if (isMoving) return DeviceState.moving;
      // Client rule: Idle = engine/ignition ON + not moving
      if (isEngineConsideredOn) return DeviceState.idle;
      // Connected, parked, engine off (or ignition not reported)
      if (status == 'online' || position != null) return DeviceState.online;
      return DeviceState.offline;
    }

    if (isMoving) return DeviceState.moving;
    if (isEngineConsideredOn) return DeviceState.idle;
    return DeviceState.offline;
  }

  String get stateLabel {
    switch (state) {
      case DeviceState.online:
        return 'Online';
      case DeviceState.offline:
        return 'Offline';
      case DeviceState.moving:
        return 'Moving';
      case DeviceState.idle:
        return 'Idle';
      case DeviceState.unknown:
        return 'Unknown';
    }
  }

  DeviceViewModel copyWith({
    DeviceModel? device,
    PositionModel? position,
    String? lastEngineCommand,
    bool clearLastEngineCommand = false,
  }) {
    return DeviceViewModel(
      device: device ?? this.device,
      position: position ?? this.position,
      lastEngineCommand: clearLastEngineCommand
          ? null
          : (lastEngineCommand ?? this.lastEngineCommand),
    );
  }
}
