import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

String stringValue(Object? value, {required String fallback}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

num numValue(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, dynamic> mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<dynamic> listValue(Object? value) {
  if (value is List) return value;
  return const [];
}

DateTime? dateTimeFromDynamic(Object? value) {
  if (value == null) return null;

  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  return DateTime.tryParse(value.toString());
}

LatLng? latLngFromDynamic(Object? value) {
  // CRITICAL FIX: Properly handle null values to prevent NullPointerException
  if (value == null) return null;

  if (value is GeoPoint) {
    return LatLng(value.latitude, value.longitude);
  }

  if (value is List && value.length >= 2) {
    final lat = numValue(value[0]).toDouble();
    final lng = numValue(value[1]).toDouble();
    // Guard: Return null for invalid coordinates (0, 0)
    if (lat == 0.0 && lng == 0.0) return null;
    return LatLng(lat, lng);
  }

  final data = mapValue(value);
  if (data.isEmpty) return null;

  final lat = numValue(data['lat'] ?? data['latitude']).toDouble();
  final lng = numValue(data['lng'] ?? data['longitude']).toDouble();
  
  // Guard: Return null for invalid coordinates (0, 0)
  if (lat == 0.0 && lng == 0.0) return null;

  return LatLng(lat, lng);
}
