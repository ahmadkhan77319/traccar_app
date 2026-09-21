import 'package:flutter/material.dart';
import '../../../constants/color.dart';
import '../../../model/device_view_model/device_view_model.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.state});

  final DeviceState state;

  Color get _color {
    switch (state) {
      case DeviceState.moving:
        return kMovingColor;
      case DeviceState.online:
        return kOnlineColor;
      case DeviceState.idle:
        return kIdleColor;
      case DeviceState.offline:
        return kOfflineColor;
      case DeviceState.unknown:
        return kUnknownColor;
    }
  }

  String get _label {
    switch (state) {
      case DeviceState.moving:
        return 'Moving';
      case DeviceState.idle:
        return 'Idle';
      case DeviceState.online:
        return 'Online';
      case DeviceState.offline:
        return 'Offline';
      case DeviceState.unknown:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            _label,
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
