import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../models/shipment.dart';

class ApiService {
  ApiService({http.Client? client, Future<String?> Function()? getToken}) 
      : _client = client ?? http.Client(),
        _getToken = getToken;

  final http.Client _client;
  final Future<String?> Function()? _getToken;

  Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    if (_getToken != null) {
      final token = await _getToken!();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<List<Shipment>> fetchRecentShipments() async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/shipments');
    final response = await _client.get(uri, headers: await _getHeaders());

    if (response.statusCode >= 400) {
      throw Exception('Unable to load shipments');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (body['shipments'] as List<dynamic>? ?? const []);

    return items
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map((item) => Shipment.fromMap(
              item['id']?.toString() ?? item['shipment_id']?.toString() ?? '',
              item,
            ))
        .toList();
  }

  Future<Map<String, dynamic>> fetchStats() async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/stats');
    final response = await _client.get(uri, headers: await _getHeaders());

    if (response.statusCode >= 400) {
      throw Exception('Unable to load stats');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['stats'] as Map);
  }

  Future<Shipment> fetchShipment(String shipmentId) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/shipments/$shipmentId');
    final response = await _client.get(uri, headers: await _getHeaders());

    if (response.statusCode >= 400) {
      throw Exception('Backend returned ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return Shipment.fromMap(
      shipmentId,
      Map<String, dynamic>.from(body['shipment'] as Map),
    );
  }

  Stream<Shipment> watchShipment(String shipmentId) async* {
    while (true) {
      yield await fetchShipment(shipmentId);
      await Future<void>.delayed(AppConfig.backendPollInterval);
    }
  }

  Future<void> updateLocation({
    required String shipmentId,
    required double lat,
    required double lng,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/update-location');
    final response = await _client.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode({
        'shipment_id': shipmentId,
        'lat': lat,
        'lng': lng,
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception('Location update failed');
    }
  }

  Future<void> analyzeShipment(String shipmentId) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/shipments/analyze');
    final response = await _client.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode({'shipment_id': shipmentId}),
    );

    if (response.statusCode >= 400) {
      throw Exception('AI analysis failed');
    }
  }

  Future<void> startBackendSimulator() async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/simulator/start');
    final response = await _client.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode({
        'shipment_id': 'SHP001',
        'origin': 'Chennai',
        'destination': 'Bangalore'
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception('Simulator failed to start');
    }
  }

  Future<void> stopBackendSimulator() async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/simulator/stop');
    await _client.post(uri, headers: await _getHeaders());
  }
}
