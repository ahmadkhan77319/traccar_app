import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../constants/color.dart';
import '../../constants/string.dart';
import '../../controllers/device_detail_controller/device_detail_controller.dart';
import '../../controllers/engine_state_controller/engine_state_controller.dart';
import '../../model/device_view_model/device_view_model.dart';
import '../../model/engine_state/engine_state.dart';
import '../../utills/common.dart';
import '../../widgets/cards/status_chip.dart';
import '../../widgets/map/live_map_widget.dart';

class DeviceMapScreen extends StatefulWidget {
  const DeviceMapScreen({
    super.key,
    required this.deviceId,
    this.initial,
  });

  final int deviceId;
  final DeviceViewModel? initial;

  @override
  State<DeviceMapScreen> createState() => _DeviceMapScreenState();
}

class _DeviceMapScreenState extends State<DeviceMapScreen> {
  late final String _tag;
  late final DeviceDetailController controller;

  @override
  void initState() {
    super.initState();
    _tag = 'device_${widget.deviceId}';
    controller = Get.put(
      DeviceDetailController(
        deviceId: widget.deviceId,
        initial: widget.initial,
      ),
      tag: _tag,
    );
  }

  @override
  void dispose() {
    if (Get.isRegistered<DeviceDetailController>(tag: _tag)) {
      Get.delete<DeviceDetailController>(tag: _tag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        final device = controller.deviceView.value;
        if (controller.isLoading.value && device == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (device == null) {
          return const Center(
            child: Text('Device not found', style: TextStyle(color: Colors.white)),
          );
        }

        final lastCmd = controller.lastEngineCommand.value;
        final engineStopped = controller.isEngineStopped;
        final engineCtrl = Get.find<EngineStateController>();
        final engineRx = engineCtrl.engineStateFor(device.id);
        final engineState = engineRx.value;
        final confirmed = engineCtrl.lastConfirmedOf(device.id);
        var engineLabel = engineCtrl.labelFor(device.id);
        if (engineState == EngineState.commandFailed ||
            engineState == EngineState.unconfirmed) {
          final confirmedLabel = confirmed == EngineState.on
              ? 'Engine ON'
              : (confirmed == EngineState.off ? 'Engine OFF' : null);
          if (confirmedLabel != null) {
            engineLabel = '$engineLabel · $confirmedLabel';
          }
        }
        final ignitionMode =
            engineCtrl.tracker.usesIgnitionFallback(device.id);
        final engineSubtitle = device.position == null
            ? 'No position available yet'
            : (engineState == EngineState.pending
                ? 'Waiting for device confirmation…'
                : (engineState == EngineState.unconfirmed
                    ? 'No confirmation received in time'
                    : (engineState == EngineState.commandFailed
                        ? 'Device rejected or returned an error'
                        : (engineState == EngineState.unknown
                            ? 'Waiting for relay / blocked from Traccar'
                            : (engineState == EngineState.noRelayData
                                ? 'This tracker does not report immobilizer state'
                                : (ignitionMode
                                    ? 'Local status (device has no relay feedback)'
                                    : (lastCmd != null
                                        ? (lastCmd == 'engineResume'
                                            ? 'Updated after Resume command'
                                            : 'Updated after Stop command')
                                        : (device.hasIgnitionReport
                                            ? (device.ignition == true
                                                ? 'Ignition is ON (ACC)'
                                                : 'Ignition is OFF (ACC)')
                                            : 'Live relay state from Traccar'))))))));
        final engineColor = engineState == EngineState.on
            ? AppColors.success
            : (engineState == EngineState.off
                ? AppColors.danger
                : (engineState == EngineState.pending
                    ? AppColors.warning
                    : kUnknownColor));
        final isPending = engineState == EngineState.pending;

        return Stack(
          children: [
            Positioned.fill(
              child: LiveMapWidget(device: device, fullScreen: true),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        elevation: 2,
                        child: IconButton(
                          onPressed: () => Get.back(),
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  device.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              StatusChip(state: device.state),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.38,
              minChildSize: 0.22,
              maxChildSize: 0.72,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              deviceDetails,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${device.speedKph.toStringAsFixed(0)} km/h',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _InfoTile(
                        icon: Icons.fingerprint,
                        label: 'Unique ID',
                        value: device.uniqueId,
                      ),
                      _InfoTile(
                        icon: Icons.schedule_rounded,
                        label: 'Last Update',
                        value: Common.formatDateTime(device.lastUpdate),
                      ),
                      _InfoTile(
                        icon: Icons.location_on_outlined,
                        label: 'Address',
                        value: device.address,
                      ),
                      if (device.hasLocation)
                        _InfoTile(
                          icon: Icons.directions_rounded,
                          label: 'Coordinates',
                          value:
                              '${device.latitude!.toStringAsFixed(5)}, ${device.longitude!.toStringAsFixed(5)}',
                          onTap: () => Common.openInGoogleMaps(
                            device.latitude!,
                            device.longitude!,
                            address: device.address,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: engineColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: engineColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: engineColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                engineStopped
                                    ? Icons.power_settings_new_rounded
                                    : Icons.local_fire_department_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    engineStatus,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Text(
                                    engineLabel,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: engineColor,
                                    ),
                                  ),
                                  Text(
                                    engineSubtitle,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // One action at a time: Resume when stopped, Stop when running.
                      if (engineStopped)
                        SizedBox(
                          width: double.infinity,
                          child: _EngineActionButton(
                            label: resumeEngine,
                            icon: Icons.play_arrow_rounded,
                            color: AppColors.success,
                            loading: controller.isCommandLoading.value ||
                                isPending,
                            onTap: () => controller.resumeEngine(context),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: _EngineActionButton(
                            label: stopEngine,
                            icon: Icons.block_rounded,
                            color: AppColors.danger,
                            loading: controller.isCommandLoading.value ||
                                isPending,
                            onTap: () => controller.stopEngine(context),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      }),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: onTap != null ? AppColors.primary : AppColors.textPrimary,
      height: 1.3,
      decoration: onTap != null ? TextDecoration.underline : null,
      decorationColor: AppColors.primary.withValues(alpha: 0.5),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(value, style: valueStyle),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.location_on_rounded,
                size: 18,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _EngineActionButton extends StatelessWidget {
  const _EngineActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 50,
          alignment: Alignment.center,
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
