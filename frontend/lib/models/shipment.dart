import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/utils/data_parsers.dart';
import '../core/utils/risk_utils.dart';

class Shipment {
  const Shipment({
    required this.id,
    required this.shipmentId,
    required this.origin,
    required this.destination,
    required this.status,
    required this.currentLocation,
    required this.route,
    required this.weather,
    required this.news,
    required this.ai,
    required this.createdAt,
    required this.updatedAt,
    this.speedKmH = 0,
    this.currentStepIndex = 0,
    this.simulationSpeedModifier = 1.0,
  });

  final String id;
  final String shipmentId;
  final String origin;
  final String destination;
  final String status;
  final LatLng? currentLocation;
  final ShipmentRoute route;
  final ShipmentWeather weather;
  final List<ShipmentNewsItem> news;
  final ShipmentAiInsight ai;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double speedKmH;
  final int currentStepIndex;
  final double? simulationSpeedModifier;

  Shipment copyWith({
    String? id,
    String? shipmentId,
    String? origin,
    String? destination,
    String? status,
    LatLng? currentLocation,
    ShipmentRoute? route,
    ShipmentWeather? weather,
    List<ShipmentNewsItem>? news,
    ShipmentAiInsight? ai,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? speedKmH,
    int? currentStepIndex,
    double? simulationSpeedModifier,
  }) {
    return Shipment(
      id: id ?? this.id,
      shipmentId: shipmentId ?? this.shipmentId,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      status: status ?? this.status,
      currentLocation: currentLocation ?? this.currentLocation,
      route: route ?? this.route,
      weather: weather ?? this.weather,
      news: news ?? this.news,
      ai: ai ?? this.ai,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      speedKmH: speedKmH ?? this.speedKmH,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      simulationSpeedModifier: simulationSpeedModifier ?? this.simulationSpeedModifier,
    );
  }

  bool get hasRoute => route.path.length > 1;
  bool get hasAnalysis => ai.success || ai.explanation.isNotEmpty;
  bool get hasLiveLocation => currentLocation != null;
  RiskLevel get riskLevel => riskLevelFromText(ai.riskLevel);

  String get title {
    if (shipmentId.isNotEmpty) return shipmentId;
    if (id.isNotEmpty) return id;
    return 'Shipment';
  }

  String get routeLabel {
    final start = origin.isNotEmpty ? origin : 'Origin';
    final end = destination.isNotEmpty ? destination : 'Destination';
    return '$start to $end';
  }

  int get currentRouteIndex {
    if (currentLocation == null || route.path.isEmpty) return 0;

    var bestIndex = 0;
    var bestDistance = double.infinity;

    for (var i = 0; i < route.path.length; i++) {
      final point = route.path[i];
      final distance = (point.latitude - currentLocation!.latitude).abs() +
          (point.longitude - currentLocation!.longitude).abs();

      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  String get currentPlace {
    if (route.path.isEmpty) return 'Waiting for route';

    final progress = currentRouteIndex / route.path.length;
    if (progress < 0.20) return origin.isNotEmpty ? '$origin corridor' : 'Origin corridor';
    if (progress < 0.45) return 'En route';
    if (progress < 0.70) return 'Mid route';
    if (progress < 0.90) return 'Approaching destination';
    return destination.isNotEmpty ? '$destination approach' : 'Destination approach';
  }

  factory Shipment.fromMap(String id, Map<String, dynamic> data) {
    // routeData from backend is an array of route objects — extract the best/first
    final rawRouteData = data['routeData'];
    Map<String, dynamic> primaryRouteMap = {};
    List<Map<String, dynamic>> allRoutesList = [];

    if (rawRouteData is List && rawRouteData.isNotEmpty) {
      primaryRouteMap = mapValue(rawRouteData[0]);
      allRoutesList = rawRouteData
          .map((r) => mapValue(r))
          .toList();
    } else if (rawRouteData is Map) {
      primaryRouteMap = mapValue(rawRouteData);
    }

    return Shipment(
      id: id,
      shipmentId: stringValue(data['shipment_id'], fallback: id),
      origin: stringValue(data['origin'], fallback: ''),
      destination: stringValue(data['destination'], fallback: ''),
      status: stringValue(data['status'], fallback: 'CREATED'),
      currentLocation: latLngFromDynamic(data['current_location']),
      route: ShipmentRoute.fromMap(primaryRouteMap, allRoutesList),
      weather: ShipmentWeather.fromMap(mapValue(data['weatherData'])),
      news: listValue(data['newsData'])
          .map((item) => ShipmentNewsItem.fromMap(mapValue(item)))
          .toList(),
      ai: ShipmentAiInsight.fromMap(mapValue(data['aiResponse'])),
      createdAt: dateTimeFromDynamic(data['created_at']),
      updatedAt: dateTimeFromDynamic(data['updated_at']),
      speedKmH: numValue(data['speed_kmh']).toDouble(),
      currentStepIndex: numValue(data['current_step_index']).toInt(),
      simulationSpeedModifier: numValue(data['simulation_speed_modifier'] ?? 1.0).toDouble(),
    );
  }
}

class ShipmentRoute {
  const ShipmentRoute({
    required this.distance,
    required this.duration,
    required this.trafficDuration,
    required this.path,
    this.allRoutes = const [],
  });

  final String distance;
  final String duration;
  final String trafficDuration;
  final List<LatLng> path;
  final List<Map<String, dynamic>> allRoutes;

  factory ShipmentRoute.fromMap(
    Map<String, dynamic> data, [
    List<Map<String, dynamic>> allRoutesList = const [],
  ]) {
    return ShipmentRoute(
      distance: stringValue(data['distance'], fallback: '--'),
      duration: stringValue(data['duration'], fallback: '--'),
      trafficDuration: stringValue(data['traffic_duration'], fallback: '--'),
      path: listValue(data['path'])
          .map(latLngFromDynamic)
          .whereType<LatLng>()
          .toList(),
      allRoutes: allRoutesList,
    );
  }
}

class ShipmentWeather {
  const ShipmentWeather({
    required this.condition,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
  });

  final String condition;
  final num temperature;
  final num humidity;
  final num windSpeed;

  ShipmentWeather copyWith({
    String? condition,
    num? temperature,
    num? humidity,
    num? windSpeed,
  }) {
    return ShipmentWeather(
      condition: condition ?? this.condition,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      windSpeed: windSpeed ?? this.windSpeed,
    );
  }

  bool get hasData => condition.isNotEmpty || temperature != 0 || humidity != 0;

  factory ShipmentWeather.fromMap(Map<String, dynamic> data) {
    return ShipmentWeather(
      condition: stringValue(data['condition'], fallback: ''),
      temperature: numValue(data['temperature']),
      humidity: numValue(data['humidity']),
      windSpeed: numValue(data['windSpeed']),
    );
  }
}

class ShipmentNewsItem {
  const ShipmentNewsItem({
    required this.title,
    required this.source,
  });

  final String title;
  final String source;

  factory ShipmentNewsItem.fromMap(Map<String, dynamic> data) {
    return ShipmentNewsItem(
      title: stringValue(data['title'], fallback: ''),
      source: stringValue(data['source'], fallback: 'System'),
    );
  }
}

class ShipmentAiInsight {
  const ShipmentAiInsight({
    required this.success,
    required this.riskScore,
    required this.riskLevel,
    required this.delayPrediction,
    required this.suggestion,
    required this.explanation,
    this.optimization,
    this.allRoutes = const [],
  });

  final bool success;
  final num riskScore;
  final String riskLevel;
  final String delayPrediction;
  final String suggestion;
  final String explanation;
  final ShipmentOptimizationData? optimization;
  final List<Map<String, dynamic>> allRoutes;

  factory ShipmentAiInsight.fromMap(Map<String, dynamic> data) {
    // Parse all_routes from the AI response for multi-route display
    final allRoutesRaw = data['all_routes'];
    final List<Map<String, dynamic>> allRoutes = [];
    if (allRoutesRaw is List) {
      for (final r in allRoutesRaw) {
        if (r is Map) allRoutes.add(Map<String, dynamic>.from(r));
      }
    }

    // Structural support for enriched gateway response
    final aiInsights = data['ai_insights'] as Map<String, dynamic>?;
    final recommendation = aiInsights?['recommendation']?.toString();

    return ShipmentAiInsight(
      success: data['success'] == true || data['ai_insights'] != null,
      riskScore: numValue(data['risk_score'] ?? aiInsights?['delay_probability'] ?? 0) / (data['risk_score'] is String ? 1 : 1),
      riskLevel: stringValue(data['risk_level'] ?? data['risk_score'], fallback: 'UNKNOWN'),
      delayPrediction: stringValue(data['delay_prediction'] ?? data['estimated_time'], fallback: '--'),
      suggestion: stringValue(data['suggestion'] ?? recommendation, fallback: 'Awaiting recommendation'),
      explanation: stringValue(data['insight'] ?? data['explanation'] ?? recommendation, fallback: ''),
      optimization: data['optimization_data'] != null
          ? ShipmentOptimizationData.fromMap(mapValue(data['optimization_data']))
          : null,
      allRoutes: allRoutes,
    );
  }
}

class ShipmentOptimizationData {
  const ShipmentOptimizationData({
    required this.before,
    required this.after,
  });

  final ShipmentOptimizationValue before;
  final ShipmentOptimizationValue after;

  factory ShipmentOptimizationData.fromMap(Map<String, dynamic> data) {
    return ShipmentOptimizationData(
      before: ShipmentOptimizationValue.fromMap(mapValue(data['before'])),
      after: ShipmentOptimizationValue.fromMap(mapValue(data['after'])),
    );
  }
}

class ShipmentOptimizationValue {
  const ShipmentOptimizationValue({
    required this.time,
    required this.cost,
    required this.fuel,
  });

  final String time;
  final num cost;
  final num fuel;

  factory ShipmentOptimizationValue.fromMap(Map<String, dynamic> data) {
    return ShipmentOptimizationValue(
      time: stringValue(data['time'], fallback: '--'),
      cost: numValue(data['cost']),
      fuel: numValue(data['fuel']),
    );
  }
}
