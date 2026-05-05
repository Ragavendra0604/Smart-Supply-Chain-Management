import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationUtils {
  /// Calculates the distance between two points in meters using the Haversine formula.
  static double calculateDistance(LatLng p1, LatLng p2) {
    const double earthRadius = 6371000; // in meters
    final double lat1 = p1.latitude * math.pi / 180;
    final double lat2 = p2.latitude * math.pi / 180;
    final double dLat = (p2.latitude - p1.latitude) * math.pi / 180;
    final double dLon = (p2.longitude - p1.longitude) * math.pi / 180;

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Interpolates between two points.
  static LatLng interpolate(LatLng p1, LatLng p2, double fraction) {
    final lat = p1.latitude + (p2.latitude - p1.latitude) * fraction;
    final lng = p1.longitude + (p2.longitude - p1.longitude) * fraction;
    return LatLng(lat, lng);
  }

  /// Parses distance string like "1,234 km" to meters.
  static double parseDistance(String distance) {
    if (distance == '--') return 0;
    final clean = distance.replaceAll(',', '').toLowerCase();
    final parts = clean.trim().split(' ');
    if (parts.isEmpty) return 0;
    
    final value = double.tryParse(parts[0]) ?? 0.0;
    if (clean.contains('km')) return value * 1000;
    return value;
  }

  /// Parses duration string like "1 hour 20 mins" or "6h 45m" to seconds.
  static double parseDuration(String duration) {
    if (duration == '--' || duration.isEmpty) return 1;
    final clean = duration.toLowerCase();
    double totalSeconds = 0;
    
    // Support h, hr, hour, hours
    final hourMatch = RegExp(r'(\d+)\s*(h|hr|hour)').firstMatch(clean);
    if (hourMatch != null) {
      totalSeconds += double.parse(hourMatch.group(1)!) * 3600;
    }
    
    // Support m, min, mins, minutes
    final minMatch = RegExp(r'(\d+)\s*(m|min|minute)').firstMatch(clean);
    if (minMatch != null) {
      totalSeconds += double.parse(minMatch.group(1)!) * 60;
    }
    
    // If it's just a number (like "45 mins" but regex only got the 45)
    if (totalSeconds == 0) {
      final justNum = RegExp(r'^(\d+)$').firstMatch(clean.trim());
      if (justNum != null) {
        totalSeconds = double.parse(justNum.group(1)!) * 60;
      }
    }

    return totalSeconds > 0 ? totalSeconds : 1.0;
  }
}
