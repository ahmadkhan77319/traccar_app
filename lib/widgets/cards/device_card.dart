import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../constants/color.dart';
import '../../controllers/engine_state_controller/engine_state_controller.dart';
import '../../model/device_view_model/device_view_model.dart';
import '../../model/engine_state/engine_state.dart';
import '../../utills/common.dart';
import 'status_chip.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.onTap,
  });

  final DeviceViewModel device;
  final VoidCallback onTap;

  Color get _accent {
    switch (device.state) {
      case DeviceState.moving:
      case DeviceState.online:
        return AppColors.success;
      case DeviceState.idle:
        return AppColors.info;
      case DeviceState.offline:
        return AppColors.danger;
      case DeviceState.unknown:
        return kUnknownColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.directions_car_filled_rounded,
                      color: _accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          device.uniqueId,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusChip(state: device.state),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Metric(
                    icon: Icons.speed_rounded,
                    label: 'Speed',
                    value: '${device.speedKph.toStringAsFixed(0)} km/h',
                  ),
                  _Metric(
                    icon: Icons.schedule_rounded,
                    label: 'Updated',
                    value: Common.formatRelativeTime(device.lastUpdate),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (Get.isRegistered<EngineStateController>())
                Obx(() {
                  final engine = Get.find<EngineStateController>();
                  engine.revision.value;
                  if (!device.engineKillCapable) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    children: [
                      _EngineStatusMetric(device: device),
                      const SizedBox(height: 10),
                    ],
                  );
                }),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      device.address,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineStatusMetric extends StatelessWidget {
  const _EngineStatusMetric({required this.device});

  final DeviceViewModel device;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<EngineStateController>()) {
      return _build(device.engineStatusLabel);
    }
    final engine = Get.find<EngineStateController>();
    return Obx(() {
      engine.revision.value; // list rebuild when any device updates
      final state = engine.engineStateFor(device.id).value;
      final confirmed = engine.lastConfirmedOf(device.id);
      var label = engine.labelFor(device.id);
      if (state == EngineState.commandFailed ||
          state == EngineState.unconfirmed) {
        final confirmedLabel = confirmed == EngineState.on
            ? 'Engine ON'
            : (confirmed == EngineState.off ? 'Engine OFF' : null);
        if (confirmedLabel != null) {
          label = '$label · $confirmedLabel';
        }
      }
      // Live blocked on this position wins over everything else.
      final blocked = device.position?.attributes?['blocked'];
      if (blocked == true) {
        label = 'Engine OFF';
      } else if (blocked == false) {
        label = 'Engine ON';
      }
      return _build(label, state: state);
    });
  }

  Widget _build(String label, {EngineState? state}) {
    final isNoRelay = state == EngineState.noRelayData;
    final color = isNoRelay
        ? kUnknownColor
        : (label.contains('ON') && !label.contains('Unknown')
            ? AppColors.success
            : (label.contains('OFF')
                ? AppColors.danger
                : (label.contains('pending')
                    ? AppColors.warning
                    : kUnknownColor)));
    final icon = isNoRelay
        ? Icons.link_off_rounded
        : (label.contains('ON') && !label.contains('Unknown')
            ? Icons.local_fire_department_rounded
            : (label.contains('OFF')
                ? Icons.power_settings_new_rounded
                : (label.contains('pending')
                    ? Icons.hourglass_top_rounded
                    : Icons.help_outline_rounded)));

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Engine',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
