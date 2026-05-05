import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/utils/risk_utils.dart';
import '../models/shipment.dart';
import '../services/ai_service.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';
import '../core/utils/location_utils.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;

class DashboardController extends ChangeNotifier {
  DashboardController({
    required ApiService apiService,
    required FirebaseService firebaseService,
    required AiService aiService,
    required LocationService locationService,
  })  : _apiService = apiService,
        _firebaseService = firebaseService,
        _aiService = aiService,
        _locationService = locationService;

  final ApiService _apiService;
  final FirebaseService _firebaseService;
  final AiService _aiService;
  final LocationService _locationService;

  List<Shipment> recentShipments = const [];
  String? activeShipmentId;
  Shipment? latestShipment;
  Stream<Shipment>? activeShipmentStream;
  Map<String, dynamic>? systemStats;

  bool isBootstrapping = true;
  bool isRefreshingAi = false;
  bool isSimulating = false;
  bool isGlobalStopped = false;
  String? simulatingShipmentId;
  bool usingFirestore = false;
  String? errorMessage;
  String? successMessage;
  double simulationSpeedMultiplier = 1.0;
  DateTime? lastUpdated;

  StreamSubscription<Shipment>? _activeShipmentSubscription;
  Timer? _simulationTimer;
  Timer? _systemCheckTimer;
  StreamSubscription<bool>? _globalStopSubscription;
  String? _lastHighRiskToken;
  int _simulationIndex = 0;

  Future<void> bootstrap() async {
    isBootstrapping = true;
    notifyListeners();

    try {
      await Future.wait([
        refreshShipments(selectFirstWhenMissing: true),
        fetchSystemStats(),
      ]);

      // PRODUCTION-GRADE: Replace polling with Real-time Stream
      _globalStopSubscription?.cancel();
      if (_firebaseService.enabled) {
        _globalStopSubscription = _firebaseService.watchGlobalStopStatus().listen(_handleStatusUpdate);
      } else {
        // Fallback for non-Firebase environments (with jittered polling)
        _systemCheckTimer?.cancel();
        _systemCheckTimer = Timer.periodic(
            const Duration(seconds: 15), (_) => _pollSystemStatus());
      }

      if (activeShipmentId != null) {
        _bindShipment(activeShipmentId!);
        _apiService.logToServer('INFO', 'Dashboard bootstrapped',
            {'activeShipment': activeShipmentId});
      }
    } catch (error) {
      errorMessage = 'Unable to load dashboard data.';
      _apiService.logToServer('ERROR', 'Dashboard bootstrap failed', {'error': error.toString()});
    } finally {
      isBootstrapping = false;
      notifyListeners();
    }
  }

  void _handleStatusUpdate(bool stopped) {
    final wasStopped = isGlobalStopped;
    isGlobalStopped = stopped;

    if (isGlobalStopped && !wasStopped) {
      _stopEverythingLocally();
    }

    if (isGlobalStopped != wasStopped) {
      notifyListeners();
    }
  }

  Future<void> _pollSystemStatus() async {
    try {
      final stopped = await _apiService.fetchGlobalStopStatus();
      _handleStatusUpdate(stopped);
    } catch (_) {}
  }

  void _stopEverythingLocally() {
    isSimulating = false;
    simulatingShipmentId = null;
    _simulationTimer?.cancel();
    _activeShipmentSubscription?.cancel();
    errorMessage = '⚠️ GLOBAL SYSTEM STOP ACTIVE. All services paused.';
    notifyListeners();
  }

  Future<void> refreshShipments({bool selectFirstWhenMissing = false}) async {
    if (isGlobalStopped) return;

    final shipments = await _apiService.fetchRecentShipments();
    recentShipments = shipments;

    if (shipments.isEmpty) {
      if (selectFirstWhenMissing) {
        activeShipmentId = AppConfig.initialShipmentId.isNotEmpty
            ? AppConfig.initialShipmentId
            : null;
      }
      notifyListeners();
      return;
    }

    final preferredId = AppConfig.initialShipmentId;
    final candidateIds = [
      if (activeShipmentId != null) activeShipmentId!,
      if (preferredId.isNotEmpty) preferredId,
      shipments.first.shipmentId,
    ];

    for (final candidate in candidateIds) {
      if (shipments.any((shipment) => shipment.shipmentId == candidate)) {
        activeShipmentId = candidate;
        break;
      }
    }

    notifyListeners();
  }

  Future<void> fetchSystemStats() async {
    try {
      systemStats = await _apiService.fetchStats();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching stats: $e');
    }
  }

  void selectShipment(String shipmentId) {
    if (shipmentId == activeShipmentId) return;
    activeShipmentId = shipmentId;
    errorMessage = null;
    successMessage = null;
    _bindShipment(shipmentId);
    notifyListeners();
  }

  Future<void> analyzeActiveShipment() async {
    final shipmentId = activeShipmentId;
    if (shipmentId == null || isRefreshingAi) return;

    isRefreshingAi = true;
    notifyListeners();

    try {
      await _aiService.refreshPrediction(shipmentId);
      _apiService.logToServer(
          'INFO', 'AI analysis refreshed', {'shipmentId': shipmentId});
    } catch (e) {
      errorMessage = 'AI refresh failed. Please try again.';
      _apiService.logToServer('ERROR', 'AI refresh failed',
          {'shipmentId': shipmentId, 'error': e.toString()});
    } finally {
      isRefreshingAi = false;
      notifyListeners();
    }
  }

  Future<void> createShipment({
    required String shipmentId,
    required String origin,
    required String destination,
    String mode = 'ROAD',
    String priority = 'NORMAL',
  }) async {
    errorMessage = null;
    successMessage = null;
    notifyListeners();

    try {
      await _apiService.createShipment(
        shipmentId: shipmentId,
        origin: origin,
        destination: destination,
        mode: mode,
        priority: priority,
      );
      successMessage = 'Shipment $shipmentId created successfully ($mode).';
      _apiService.logToServer(
          'INFO', 'Manual shipment created', {'shipmentId': shipmentId, 'mode': mode});
      await refreshShipments();
      selectShipment(shipmentId);
    } catch (e) {
      errorMessage = 'Failed to create shipment: ${e.toString()}';
      _apiService.logToServer(
          'ERROR', 'Manual shipment creation failed', {'error': e.toString()});
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  /// Applies the AI-recommended optimized route for the given shipment.
  /// Calls the backend PATCH endpoint, then surfaces outcome to the UI.
  Future<void> applyOptimizedRoute(String shipmentId) async {
    errorMessage = null;
    successMessage = null;
    notifyListeners();

    try {
      await _apiService.applyRoute(shipmentId);
      successMessage =
          'Optimized route applied for $shipmentId — vehicle notified.';
      _apiService.logToServer(
          'INFO', 'Optimized route applied', {'shipmentId': shipmentId});
    } catch (e) {
      errorMessage = 'Failed to apply route. Please try again.';
      _apiService.logToServer('ERROR', 'Apply route failed',
          {'shipmentId': shipmentId, 'error': e.toString()});
    } finally {
      notifyListeners();
    }
  }

  Future<void> startLiveSimulation(Shipment shipment) async {
    isSimulating = true;
    notifyListeners();
    try {
      await _apiService.startBackendSimulator(
        shipmentId: shipment.shipmentId,
        origin: shipment.origin,
        destination: shipment.destination,
      );
      errorMessage = null;
      _apiService.logToServer('INFO', 'Simulation started', {
        'shipmentId': shipment.shipmentId,
        'route': '${shipment.origin} -> ${shipment.destination}'
      });
    } catch (e) {
      isSimulating = false;
      errorMessage = 'Failed to start live simulation';
      _apiService.logToServer(
          'ERROR', 'Failed to start simulation', {'error': e.toString()});
    } finally {
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> simulateTacticalScenario({
    required String shipmentId,
    String? weatherCondition,
    double? trafficLevel,
    double? speedModifier,
    String? modelName,
  }) async {
    try {
      final result = await _apiService.simulateShipment(
        shipmentId: shipmentId,
        weatherCondition: weatherCondition,
        trafficLevel: trafficLevel,
        speedModifier: speedModifier,
        modelName: modelName,
      );
      return result;
    } catch (e) {
      _apiService.logToServer('ERROR', 'Tactical simulation failed', {'error': e.toString()});
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> injectScenarioIntoLiveRoute({
    required String shipmentId,
    required String weatherCondition,
    required double trafficLevel,
    required double speedModifier,
  }) async {
    try {
      final result = await _apiService.injectSimulation(
        shipmentId: shipmentId,
        weatherCondition: weatherCondition,
        trafficLevel: trafficLevel,
        speedModifier: speedModifier,
      );
      if (result['success'] == true && result['analysis'] != null) {
        // Force update the local shipment state with the new AI results
        if (latestShipment != null && latestShipment!.shipmentId == shipmentId) {
          final newAi = ShipmentAiInsight.fromMap(result['analysis']);
          latestShipment = latestShipment!.copyWith(
            ai: newAi,
            weather: latestShipment!.weather.copyWith(
              condition: weatherCondition,
            ),
          );
        }
      }
      
      successMessage = 'Simulation scenario injected and AI re-analyzed.';
      _apiService.logToServer('INFO', 'Scenario injected', {
        'shipmentId': shipmentId,
        'weather': weatherCondition,
        'speedModifier': speedModifier
      });
      notifyListeners();
      return result;
    } catch (e) {
      errorMessage = 'Failed to inject scenario.';
      _apiService.logToServer('ERROR', 'Scenario injection failed', {'error': e.toString()});
      return null;
    }
  }

  void setSimulationSpeed(double value) {
    simulationSpeedMultiplier = value;
    notifyListeners();
  }

  Future<void> toggleGlobalStop(bool stopped) async {
    final wasStopped = isGlobalStopped;
    isGlobalStopped = stopped;
    notifyListeners();

    try {
      if (stopped) {
        _stopEverythingLocally();
      }

      await _apiService.toggleGlobalStop(stopped);
      
      if (stopped) {
        successMessage = 'GLOBAL STOP: All simulations and background services terminated.';
      } else {
        successMessage = 'SYSTEM RESUMED: Global Stop deactivated.';
        errorMessage = null;
        // Optionally refresh data to show system is back online
        await refreshShipments();
      }
    } catch (e) {
      isGlobalStopped = wasStopped;
      errorMessage = 'Failed to update global system status.';
    } finally {
      notifyListeners();
    }
  }

  Future<void> stopAllSimulations() async {
    await toggleGlobalStop(true);
  }

  Future<void> stopLiveSimulation() async {
    final id = simulatingShipmentId;
    final lastShipment = latestShipment;
    
    _stopSimulation(); // 1. Locally cancel timer and reset state
    
    if (id != null && lastShipment != null && lastShipment.currentLocation != null) {
      // 2. Persist the final position before marking as STOPPED
      try {
        await _locationService.sendVehicleLocation(
          shipmentId: id,
          point: lastShipment.currentLocation!,
          speedKmH: 0,
          currentStepIndex: lastShipment.currentStepIndex,
        );
      } catch (e) {
        debugPrint('Final location sync failed: $e');
      }
    }

    try {
      // 3. Sync with backend to mark as STOPPED
      await _apiService.stopBackendSimulator(shipmentId: id);
    } catch (_) {
      // Non-fatal if backend sync fails
    }
  }

  void toggleSimulation(Shipment targetShipment) async {
    if (!AppConfig.enableSimulationControls) return;
    if (isGlobalStopped) {
      errorMessage = 'Cannot start simulation: Global Stop is active.';
      notifyListeners();
      return;
    }

    if (isSimulating && simulatingShipmentId == targetShipment.shipmentId) {
      await stopLiveSimulation();
      return;
    }

    // Stop any existing simulation first
    if (isSimulating) {
      await stopLiveSimulation();
    }

    // If shipment has no route, trigger analysis first then try to start simulation
    if (!targetShipment.hasRoute) {
      errorMessage = 'No route data. Fetching optimized route via AI...';
      notifyListeners();

      try {
        await _apiService.analyzeShipment(targetShipment.shipmentId);
        // Wait a moment for the Firestore/Stream to sync the new route
        await Future.delayed(const Duration(seconds: 2));

        // Refresh the shipment object from our recent list (it should have updated via the stream)
        final refreshed = recentShipments.firstWhere(
          (s) => s.shipmentId == targetShipment.shipmentId,
          orElse: () => targetShipment,
        );

        if (!refreshed.hasRoute) {
          errorMessage = 'AI failed to provide a route. Please try again.';
          notifyListeners();
          return;
        }

        // Success! Proceed with the refreshed shipment
        targetShipment = refreshed;
      } catch (e) {
        errorMessage = 'Failed to fetch route: $e';
        notifyListeners();
        return;
      }
    }

    // Auto-select this shipment so we can see it on the map
    selectShipment(targetShipment.shipmentId);

    // If already at or near destination, restart from beginning for the demo
    int startIndex = targetShipment.currentStepIndex;
    if (startIndex >= targetShipment.route.path.length - 2) {
      debugPrint(
          'Restarting simulation from beginning for ${targetShipment.shipmentId}');
      startIndex = 0;
    }

    debugPrint(
        'Starting simulation for ${targetShipment.shipmentId} at index $startIndex');

    // FIX: If resuming (startIndex > 0), start from the NEXT point to prevent reverse movement
    _simulationIndex = (startIndex == 0) ? 0 : (startIndex + 1).clamp(0, targetShipment.route.path.length - 1);
    isSimulating = true;
    simulatingShipmentId = targetShipment.shipmentId;
    errorMessage = null;
    successMessage = null;
    notifyListeners();

    _simulationTimer = Timer.periodic(
      AppConfig.simulationStepInterval,
      (_) => _advanceSimulation(targetShipment.shipmentId),
    );
  }

  bool consumeHighRiskAlert(Shipment shipment) {
    if (shipment.riskLevel != RiskLevel.high) return false;

    final token =
        '${shipment.shipmentId}:${shipment.ai.riskLevel}:${shipment.ai.delayPrediction}';
    if (_lastHighRiskToken == token) return false;

    _lastHighRiskToken = token;
    return true;
  }

  void _bindShipment(String shipmentId) {
    _activeShipmentSubscription?.cancel();
    usingFirestore = _firebaseService.enabled;

    final stream = (_firebaseService.enabled
            ? _firebaseService.watchShipment(shipmentId)
            : _apiService.watchShipment(shipmentId))
        .asBroadcastStream();

    activeShipmentStream = stream;
    _activeShipmentSubscription = stream.listen(
      (shipment) {
        latestShipment = shipment;
        lastUpdated = DateTime.now();
        errorMessage = null;
        _syncShipmentSummary(shipment);
        notifyListeners();
      },
      onError: (e) {
        debugPrint('🔥 FIREBASE STREAM ERROR: $e');
        _apiService.logToServer('ERROR', 'Firebase Stream Failed', {'error': e.toString(), 'shipmentId': shipmentId});
        
        usingFirestore = false;
        errorMessage =
            'Live stream unavailable. Falling back to backend polling.';
        activeShipmentStream =
            _apiService.watchShipment(shipmentId).asBroadcastStream();
        _activeShipmentSubscription = activeShipmentStream!.listen(

          (shipment) {
            latestShipment = shipment;
            lastUpdated = DateTime.now();
            errorMessage = null;
            _syncShipmentSummary(shipment);
            notifyListeners();
          },
          onError: (_) {
            errorMessage = 'Unable to connect to live shipment updates.';
            notifyListeners();
          },
        );
        notifyListeners();
      },
    );
  }

  Future<void> _advanceSimulation(String targetId) async {
    final shipment = recentShipments.firstWhere(
      (s) => s.shipmentId == targetId,
      orElse: () => latestShipment!,
    );

    if (shipment.route.path.isEmpty || _simulationIndex >= shipment.route.path.length) {
      _stopSimulation();
      return;
    }

    final currentPoint = shipment.currentLocation ?? shipment.route.path[0];
    
    // 1. Calculate base speed from route data (Distance / Duration)
    final distanceMeters = LocationUtils.parseDistance(shipment.route.distance);
    final durationSeconds = LocationUtils.parseDuration(
      shipment.route.trafficDuration != '--' 
        ? shipment.route.trafficDuration 
        : shipment.route.duration
    );
    
    double calculatedSpeedKmH = (distanceMeters / durationSeconds) * 3.6;
    
    // Sanitize speed for a truck (avoiding extremes if route data is sparse)
    if (calculatedSpeedKmH < 30) calculatedSpeedKmH = 45.0;
    if (calculatedSpeedKmH > 110) calculatedSpeedKmH = 85.0;

    // 2. Apply dynamic environmental modifiers
    double modifier = 1.0;
    
    // Weather impact
    final weather = shipment.weather.condition.toLowerCase();
    if (weather.contains('rain') || weather.contains('snow') || weather.contains('storm')) {
      modifier *= 0.75; // Slow down for bad weather
    }
    
    // Risk/Safety impact
    if (shipment.ai.riskLevel.toUpperCase() == 'HIGH') {
      modifier *= 0.80; // Precautionary slowdown for high-risk zones
    }

    // Final dynamic speed with slight natural jitter
    final double injectedModifier = shipment.simulationSpeedModifier ?? 1.0;
    final double targetSpeedKmH = (calculatedSpeedKmH * modifier * injectedModifier) + 
        (math.Random().nextDouble() * 4.0 - 2.0);

    final double intervalSeconds = AppConfig.simulationStepInterval.inMilliseconds / 1000.0;
    
    // Distance to cover in this interval (meters)
    double distanceToCover = (targetSpeedKmH * 1000 / 3600) * intervalSeconds * simulationSpeedMultiplier;
    
    LatLng nextPoint = currentPoint;
    int nextIndex = _simulationIndex;

    // Move along the path until we've covered the distance or reached the end
    while (distanceToCover > 0 && nextIndex < shipment.route.path.length) {
      final point = shipment.route.path[nextIndex];
      final distToNext = LocationUtils.calculateDistance(nextPoint, point);

      if (distToNext <= distanceToCover) {
        distanceToCover -= distToNext;
        nextPoint = point;
        nextIndex++;
      } else {
        // Interpolate between current position and next waypoint
        final fraction = distanceToCover / distToNext;
        nextPoint = LocationUtils.interpolate(nextPoint, point, fraction);
        distanceToCover = 0;
      }
    }

    _simulationIndex = nextIndex;
    final isDestination = _simulationIndex >= shipment.route.path.length - 1 && distanceToCover >= 0;

    final updatedShipment = shipment.copyWith(
      currentLocation: nextPoint,
      status: isDestination ? 'DELIVERED' : 'IN_TRANSIT',
      speedKmH: isDestination ? 0 : targetSpeedKmH,
    );

    if (isDestination) {
      successMessage = 'Shipment $targetId has arrived at its destination!';
    }

    _syncShipmentSummary(updatedShipment);
    if (activeShipmentId == targetId) {
      latestShipment = updatedShipment;
    }
    notifyListeners();

    try {
      await _locationService.sendVehicleLocation(
        shipmentId: targetId,
        point: nextPoint,
        speedKmH: updatedShipment.speedKmH,
        currentStepIndex: _simulationIndex,
      );
      if (isDestination) {
        _stopSimulation();
        // Trigger post-delivery AI summary and state finalization
        try {
          final summaryData = await _apiService.completeShipment(targetId);
          if (activeShipmentId == targetId) {
            latestShipment = latestShipment!.copyWith(
              status: 'DELIVERED',
              deliverySummary: DeliverySummary.fromMap(summaryData),
            );
            _syncShipmentSummary(latestShipment!);
            notifyListeners();
          }
        } catch (e) {
          debugPrint('Post-delivery completion failed: $e');
        }
      }
    } catch (_) {
      errorMessage = 'Simulation update failed.';
    }
  }

  void _syncShipmentSummary(Shipment shipment) {
    final index = recentShipments.indexWhere(
      (item) => item.shipmentId == shipment.shipmentId,
    );

    if (index == -1) {
      recentShipments = [shipment, ...recentShipments];
      return;
    }

    final updated = [...recentShipments];
    updated[index] = shipment;
    recentShipments = updated;
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    isSimulating = false;
    simulatingShipmentId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _activeShipmentSubscription?.cancel();
    _globalStopSubscription?.cancel();
    _simulationTimer?.cancel();
    _systemCheckTimer?.cancel();
    super.dispose();
  }
}
