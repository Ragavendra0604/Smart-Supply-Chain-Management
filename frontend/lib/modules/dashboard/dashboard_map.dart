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

  @override
  void didUpdateWidget(covariant DashboardMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCamera();
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
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      polylines: {
        if (path.length > 1)
          Polyline(
            polylineId: const PolylineId('shipment_route'),
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
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('vehicle'),
        position: current,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          riskMarkerHue(widget.shipment.riskLevel),
        ),
        infoWindow: const InfoWindow(title: 'Live vehicle'),
      ),
      Marker(
        markerId: const MarkerId('current_pin'),
        position: current,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: InfoWindow(title: widget.shipment.currentPlace),
      ),
    };

    if (path.isNotEmpty) {
      markers.add(
        Marker(
          markerId: const MarkerId('origin'),
          position: path.first,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: widget.shipment.origin),
        ),
      );

      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: path.last,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: widget.shipment.destination),
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
        '${widget.shipment.shipmentId}:${current.latitude}:${current.longitude}:${path.length}:${path.isNotEmpty ? path.first.latitude : 0}:${path.isNotEmpty ? path.last.longitude : 0}';

    if (!forceFit && viewportKey == _lastViewportKey) {
      return;
    }

    _lastViewportKey = viewportKey;

    if (path.length > 1 && forceFit) {
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(MapUtils.boundsFor(path), 70),
      );
      return;
    }

    controller.animateCamera(CameraUpdate.newLatLng(current));
  }
}
