import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'api_service.dart';

class LocationService {
  const LocationService(this._apiService);

  final ApiService _apiService;

  Future<void> sendVehicleLocation({
    required String shipmentId,
    required LatLng point,
  }) {
    return _apiService.updateLocation(
      shipmentId: shipmentId,
      lat: point.latitude,
      lng: point.longitude,
    );
  }
}
