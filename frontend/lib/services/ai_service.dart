import 'api_service.dart';

class AiService {
  const AiService(this._apiService);

  final ApiService _apiService;

  Future<void> refreshPrediction(String shipmentId) {
    return _apiService.analyzeShipment(shipmentId);
  }
}
