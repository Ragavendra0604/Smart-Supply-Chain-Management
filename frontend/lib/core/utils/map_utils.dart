import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapUtils {
  static const LatLng defaultCenter = LatLng(12.9716, 77.5946);

  static LatLng fallbackCenter(List<LatLng> path, LatLng? currentLocation) {
    if (currentLocation != null) return currentLocation;
    if (path.isNotEmpty) return path.first;
    return defaultCenter;
  }

  static LatLngBounds boundsFor(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}
