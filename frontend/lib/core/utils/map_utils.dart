import 'dart:math' as math;
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

  static double calculateBearing(LatLng start, LatLng end) {
    final double startLat = _degreesToRadians(start.latitude);
    final double startLong = _degreesToRadians(start.longitude);
    final double endLat = _degreesToRadians(end.latitude);
    final double endLong = _degreesToRadians(end.longitude);

    final double dLong = endLong - startLong;

    final double y = math.sin(dLong) * math.cos(endLat);
    final double x = math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLong);

    final double bearing = math.atan2(y, x);
    return (_radiansToDegrees(bearing) + 360) % 360;
  }

  static double _degreesToRadians(double degrees) => degrees * math.pi / 180;
  static double _radiansToDegrees(double radians) => radians * 180 / math.pi;
}
