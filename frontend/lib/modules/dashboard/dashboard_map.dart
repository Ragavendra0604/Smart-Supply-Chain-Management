import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/utils/map_utils.dart';
import '../../core/utils/risk_utils.dart';
import '../../models/shipment.dart';

class DashboardMap extends StatefulWidget {
  const DashboardMap({
    required this.shipment,
    super.key,
  });

  final Shipment shipment;

  @override
  State<DashboardMap> createState() => _DashboardMapState();
}

class _DashboardMapState extends State<DashboardMap> {
  GoogleMapController? _mapController;
  String? _lastViewportKey;
  BitmapDescriptor? _truckIcon;

  @override
  void initState() {
    super.initState();
    _loadTruckIcon();
  }

  Future<void> _loadTruckIcon() async {
    final icon = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/images/truck.png',
    );
    if (mounted) {
      setState(() {
        _truckIcon = icon;
      });
    }
  }

  @override
  void didUpdateWidget(covariant DashboardMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Force fit bounds if the shipment ID changed or if we just got a path
    final pathChanged = widget.shipment.route.path.length != oldWidget.shipment.route.path.length;
    final idChanged = widget.shipment.shipmentId != oldWidget.shipment.shipmentId;
    
    _syncCamera(forceFit: idChanged || pathChanged);
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.shipment.route.path;
    final current = MapUtils.fallbackCenter(path, widget.shipment.currentLocation);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: current, zoom: 8),
      onMapCreated: (controller) {
        _mapController = controller;
        _syncCamera(forceFit: true);
      },
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true, // Enabled for better UX
      compassEnabled: true,
      mapToolbarEnabled: true,
      trafficEnabled: true,
      polylines: {
        if (path.length > 1)
          Polyline(
            polylineId: PolylineId('route_${widget.shipment.shipmentId}'),
            points: path,
            width: 6,
            color: const Color(0xFF2563EB),
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
      },
      markers: _buildMarkers(path, current),
    );
  }

  Set<Marker> _buildMarkers(List<LatLng> path, LatLng current) {
    double rotation = 0;
    
    // Calculate rotation if we have path data
    if (path.isNotEmpty) {
      final index = widget.shipment.currentRouteIndex;
      if (index > 0 && index < path.length) {
        rotation = MapUtils.calculateBearing(path[index - 1], path[index]);
      } else if (index == 0 && path.length > 1) {
        rotation = MapUtils.calculateBearing(path[0], path[1]);
      }
    }

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('vehicle'),
        position: current,
        rotation: rotation,
        anchor: const Offset(0.5, 0.5),
        icon: _truckIcon ?? BitmapDescriptor.defaultMarkerWithHue(
          riskMarkerHue(widget.shipment.riskLevel),
        ),
        infoWindow: InfoWindow(
          title: 'Shipment ${widget.shipment.shipmentId}',
          snippet: widget.shipment.currentPlace,
        ),
        zIndexInt: 2,
      ),
    };

    if (path.isNotEmpty) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: path.first,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Origin: ${widget.shipment.origin}'),
        ),
      );

      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: path.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: 'Destination: ${widget.shipment.destination}'),
        ),
      );
    }

    return markers;
  }

  void _syncCamera({bool forceFit = false}) {
    final controller = _mapController;
    if (controller == null) return;

    final path = widget.shipment.route.path;
    final current = MapUtils.fallbackCenter(path, widget.shipment.currentLocation);
    final viewportKey =
        '${widget.shipment.shipmentId}:${current.latitude}:${current.longitude}:${path.length}';

    if (!forceFit && viewportKey == _lastViewportKey) {
      return;
    }

    _lastViewportKey = viewportKey;

    if (path.length > 1 && forceFit) {
      try {
        controller.animateCamera(
          CameraUpdate.newLatLngBounds(MapUtils.boundsFor(path), 70),
        );
        return;
      } catch (e) {
        debugPrint('Error fitting bounds: $e');
      }
    }

    controller.animateCamera(CameraUpdate.newLatLng(current));
  }
}
