import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final headers = {
      'Content-Type': 'application/json',
      'x-idempotency-key': 'req-$timestamp',
    };
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

  /// Streams a shipment, falling back with exponential backoff + jitter
  /// on repeated failures instead of hammering the backend in a tight loop.
  Stream<Shipment> watchShipment(String shipmentId) async* {
    var failCount = 0;
    const maxBackoffMs = 30000; // cap at 30 seconds

    while (true) {
      try {
        final s = await fetchShipment(shipmentId);
        failCount = 0; // reset on success
        yield s;
        await Future<void>.delayed(AppConfig.backendPollInterval);
      } catch (_) {
        failCount++;
        // Exponential backoff: 1s, 2s, 4s, 8s … capped at 30s + random jitter
        final backoffMs = (1000 * (1 << failCount.clamp(0, 5)))
            .clamp(0, maxBackoffMs);
        final jitterMs = (backoffMs * 0.2 *
            (DateTime.now().millisecondsSinceEpoch % 100) / 100)
            .toInt();
        await Future<void>.delayed(
            Duration(milliseconds: backoffMs + jitterMs));
      }
    }
  }

  Future<void> updateLocation({
    required String shipmentId,
    required double lat,
    required double lng,
    double speedKmH = 0,
    int currentStepIndex = 0,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/update-location');
    // final response = await _client.post(
    //   uri,
    //   headers: await _getHeaders(),
    //   body: jsonEncode({
    try {
      final response = await _client.post(
        uri,
        headers: await _getHeaders(),
        body: jsonEncode({
          'shipment_id': shipmentId,
          'lat': lat,
          'lng': lng,
          'speed_kmh': speedKmH,
          'current_step_index': currentStepIndex,
        }),
      );

      if (response.statusCode >= 400) {
        throw Exception('Location update failed');
      }
    } catch (e) {
      throw Exception('Failed to update location: $e');
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

  Future<Map<String, dynamic>> simulateShipment({
    required String shipmentId,
    String? weatherCondition,
    double? trafficLevel,
    double? speedModifier,
    String? modelName,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/shipments/simulate');
    final response = await _client.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode({
        'shipment_id': shipmentId,
        'weatherCondition': weatherCondition,
        'trafficLevel': trafficLevel,
        'speedModifier': speedModifier,
        'model_name': modelName,
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception('Simulation failed');
    }

    final body = jsonDecode(response.body);
    return Map<String, dynamic>.from(body['simulation'] as Map);
  }

  Future<Map<String, dynamic>> injectSimulation({
    required String shipmentId,
    required String weatherCondition,
    required double trafficLevel,
    required double speedModifier,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/inject-simulation');
    final response = await _client.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode({
        'shipment_id': shipmentId,
        'weatherCondition': weatherCondition,
        'trafficLevel': trafficLevel,
        'speedModifier': speedModifier,
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception('Scenario injection failed');
    }
    
    return jsonDecode(response.body);
  }

  Future<void> createShipment({
    required String shipmentId,
    required String origin,
    required String destination,
    String mode = 'ROAD',
    String priority = 'NORMAL',
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/create-shipment');
    final response = await _client.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode({
        'shipment_id': shipmentId,
        'origin': origin,
        'destination': destination,
        'mode': mode,
        'priority': priority,
      }),
    );

    if (response.statusCode >= 400) {
      throw Exception('Failed to create shipment');
    }
  }

  /// Applies the AI-recommended route for a shipment.
  /// Writes status = ROUTE_APPLIED to Firestore via the backend.
  Future<void> applyRoute(String shipmentId) async {
    final uri = Uri.parse(
        '${AppConfig.apiBaseUrl}/api/shipments/$shipmentId/apply-route');
    final response = await _client.patch(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode({'shipment_id': shipmentId}),
    );

    if (response.statusCode >= 400) {
      throw Exception('Failed to apply route (${response.statusCode})');
    }
  }

  Future<void> startBackendSimulator({
    required String shipmentId,
    required String origin,
    required String destination,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/simulator/start');
    final response = await _client.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode({
        'shipment_id': shipmentId,
        'origin': origin,
        'destination': destination,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception('Simulator failed to start');
    }
  }

  Future<void> stopBackendSimulator({String? shipmentId}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/simulator/stop');
    await _client.post(
      uri,
      headers: await _getHeaders(),
      body: shipmentId != null ? jsonEncode({'shipment_id': shipmentId}) : null,
    );
  }

  Future<void> logToServer(String level, String message, [Map<String, dynamic>? data]) async {
    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/logs');
      await _client.post(
        uri,
        headers: await _getHeaders(),
        body: jsonEncode({
          'level': level,
          'message': message,
          'data': data,
        }),
      );
    } catch (e) {
      debugPrint('Remote logging failed: $e');
    }
  }

  Future<bool> fetchGlobalStopStatus() async {
    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/system/status');
      final response = await _client.get(uri, headers: await _getHeaders());
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['config']?['isGlobalStopped'] ?? false;
      }
    } catch (_) {}
    return false;
  }

  Future<void> toggleGlobalStop(bool stopped) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/system/toggle-stop');
    await _client.post(
      uri,
      headers: await _getHeaders(),
      body: jsonEncode({'stopped': stopped}),
    );
  }
}

