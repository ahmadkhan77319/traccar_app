import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../constants/color.dart';
import '../../model/device_view_model/device_view_model.dart';

class LiveMapWidget extends StatefulWidget {
  const LiveMapWidget({
    super.key,
    required this.device,
    this.height = 280,
    this.fullScreen = false,
    this.onMapCreated,
  });

  final DeviceViewModel device;
  final double height;
  final bool fullScreen;
  final ValueChanged<GoogleMapController>? onMapCreated;

  @override
  State<LiveMapWidget> createState() => _LiveMapWidgetState();
}

class _LiveMapWidgetState extends State<LiveMapWidget> {
  static const double _markerWidth = 28;

  GoogleMapController? _mapController;
  BitmapDescriptor? _greenIcon;
  BitmapDescriptor? _redIcon;
  BitmapDescriptor? _blueIcon;
  BitmapDescriptor? _orangeIcon;
  BitmapDescriptor? _greyIcon;
  bool _iconsReady = false;
  LatLng? _lastCenter;

  @override
  void initState() {
    super.initState();
    _loadVehicleIcons();
  }

  Future<void> _loadVehicleIcons() async {
    const config = ImageConfiguration();
    final loaded = await Future.wait([
      BitmapDescriptor.asset(config, 'assets/tbtrack/car_toprunning.png', width: _markerWidth),
      BitmapDescriptor.asset(config, 'assets/tbtrack/car_topstop.png', width: _markerWidth),
      BitmapDescriptor.asset(config, 'assets/tbtrack/car_topinactive.png', width: _markerWidth),
      BitmapDescriptor.asset(config, 'assets/tbtrack/car_topoverspeed.png', width: _markerWidth),
      BitmapDescriptor.asset(config, 'assets/tbtrack/car_topnodata.png', width: _markerWidth),
    ]);
    if (!mounted) return;
    _greenIcon = loaded[0];
    _redIcon = loaded[1];
    _blueIcon = loaded[2];
    _orangeIcon = loaded[3];
    _greyIcon = loaded[4];
    setState(() => _iconsReady = true);
  }

  BitmapDescriptor _iconFor(DeviceViewModel device) {
    switch (device.state) {
      case DeviceState.moving:
      case DeviceState.online:
        return _greenIcon ?? BitmapDescriptor.defaultMarker;
      case DeviceState.idle:
        if (device.hasIgnitionReport && device.engineOn == false) {
          return _orangeIcon ?? _blueIcon ?? BitmapDescriptor.defaultMarker;
        }
        return _blueIcon ?? BitmapDescriptor.defaultMarker;
      case DeviceState.offline:
        return _redIcon ?? BitmapDescriptor.defaultMarker;
      case DeviceState.unknown:
        return _greyIcon ?? BitmapDescriptor.defaultMarker;
    }
  }

  @override
  void didUpdateWidget(covariant LiveMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lat = widget.device.latitude;
    final lng = widget.device.longitude;
    if (lat == null || lng == null) return;
    final next = LatLng(lat, lng);
    if (_lastCenter == null ||
        _lastCenter!.latitude != next.latitude ||
        _lastCenter!.longitude != next.longitude) {
      _lastCenter = next;
      _mapController?.animateCamera(CameraUpdate.newLatLng(next));
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasLocation = widget.device.hasLocation;
    final center = hasLocation
        ? LatLng(widget.device.latitude!, widget.device.longitude!)
        : const LatLng(31.5204, 74.3587);

    final markers = <Marker>{};
    if (hasLocation && _iconsReady) {
      markers.add(
        Marker(
          markerId: MarkerId('device_${widget.device.id}'),
          position: center,
          rotation: widget.device.course,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: _iconFor(widget.device),
          infoWindow: InfoWindow(
            title: widget.device.name,
            snippet:
                '${widget.device.speedKph.toStringAsFixed(0)} km/h · ${widget.device.stateLabel}',
          ),
        ),
      );
    }

    final map = GoogleMap(
      initialCameraPosition: CameraPosition(
        target: center,
        zoom: hasLocation ? 15.4 : 11,
      ),
      markers: markers,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: true,
      mapToolbarEnabled: false,
      onMapCreated: (controller) {
        _mapController = controller;
        if (hasLocation) _lastCenter = center;
        widget.onMapCreated?.call(controller);
      },
    );

    if (widget.fullScreen) {
      return Stack(
        children: [
          Positioned.fill(child: map),
          if (!hasLocation)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: const Text(
                  'Waiting for live location…',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 56,
            right: 12,
            child: _MapFab(
              icon: Icons.my_location_rounded,
              onTap: hasLocation
                  ? () => _mapController?.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(target: center, zoom: 16),
                        ),
                      )
                  : null,
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            map,
            if (!hasLocation)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: const Text(
                  'Waiting for live location…',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            Positioned(
              top: 10,
              right: 10,
              child: _MapFab(
                icon: Icons.my_location_rounded,
                onTap: hasLocation
                    ? () => _mapController?.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(target: center, zoom: 16),
                          ),
                        )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  const _MapFab({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
      ),
    );
  }
}
