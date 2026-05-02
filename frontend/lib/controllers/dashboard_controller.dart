import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/utils/risk_utils.dart';
import '../models/shipment.dart';
import '../services/ai_service.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../services/location_service.dart';

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
  DateTime? lastUpdated;

  StreamSubscription<Shipment>? _activeShipmentSubscription;
  Timer? _simulationTimer;
  Timer? _systemCheckTimer;
  String? _lastHighRiskToken;
  int _simulationIndex = 0;

  Future<void> bootstrap() async {
    isBootstrapping = true;
    notifyListeners();

    try {
      await Future.wait([
        refreshShipments(selectFirstWhenMissing: true),
        fetchSystemStats(),
        _checkSystemStatus(),
      ]);

      // Start periodic system check
      _systemCheckTimer?.cancel();
      _systemCheckTimer = Timer.periodic(
          const Duration(seconds: 10), (_) => _checkSystemStatus());

      if (activeShipmentId != null) {
        _bindShipment(activeShipmentId!);
        _apiService.logToServer('INFO', 'Dashboard bootstrapped',
            {'activeShipment': activeShipmentId});
      } else {
        errorMessage =
            'No shipments found. Create or analyze a shipment first.';
        _apiService.logToServer(
            'WARNING', 'No shipments found during bootstrap');
      }
    } catch (error) {
      errorMessage = 'Unable to load dashboard data.';
      _apiService.logToServer(
          'ERROR', 'Dashboard bootstrap failed', {'error': error.toString()});
    } finally {
      isBootstrapping = false;
      notifyListeners();
    }
  }

  Future<void> _checkSystemStatus() async {
    final wasStopped = isGlobalStopped;
    isGlobalStopped = await _apiService.fetchGlobalStopStatus();

    if (isGlobalStopped && !wasStopped) {
      _stopEverythingLocally();
    }

    if (isGlobalStopped != wasStopped) {
      notifyListeners();
    }
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
  }) async {
    errorMessage = null;
    successMessage = null;
    notifyListeners();

    try {
      await _apiService.createShipment(
        shipmentId: shipmentId,
        origin: origin,
        destination: destination,
      );
      successMessage = 'Shipment $shipmentId created successfully.';
      _apiService.logToServer(
          'INFO', 'Manual shipment created', {'shipmentId': shipmentId});
      await refreshShipments();
      selectShipment(shipmentId);
    } catch (e) {
      errorMessage = 'Failed to create shipment: ${e.toString()}';
      _apiService.logToServer(
          'ERROR', 'Manual shipment creation failed', {'error': e.toString()});
      throw e;
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

  Future<void> stopAllSimulations() async {
    isSimulating = false;
    simulatingShipmentId = null;
    isGlobalStopped = true;
    notifyListeners();
    try {
      // 1. Locally stop everything
      _stopEverythingLocally();

      // 2. Persist Global Stop in Firestore via Backend
      await _apiService.toggleGlobalStop(true);

      successMessage =
          'GLOBAL STOP: All simulations and background services terminated.';
    } catch (e) {
      errorMessage = 'Failed to stop all services globally.';
    } finally {
      notifyListeners();
    }
  }

  Future<void> stopLiveSimulation() async {
    final id = simulatingShipmentId;
    isSimulating = false;
    simulatingShipmentId = null;
    notifyListeners();
    try {
      await _apiService.stopBackendSimulator(shipmentId: id);
    } catch (_) {}
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
    int startIndex = targetShipment.currentRouteIndex;
    if (startIndex >= targetShipment.route.path.length - 2) {
      debugPrint(
          'Restarting simulation from beginning for ${targetShipment.shipmentId}');
      startIndex = 0;
    }

    debugPrint(
        'Starting simulation for ${targetShipment.shipmentId} at index $startIndex');

    _simulationIndex = startIndex;
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
    // Find the shipment in the current list to get latest path
    final shipment = recentShipments.firstWhere(
      (s) => s.shipmentId == targetId,
      orElse: () => latestShipment!,
    );

    if (shipment.route.path.isEmpty) {
      _stopSimulation();
      return;
    }

    if (_simulationIndex >= shipment.route.path.length) {
      _stopSimulation();
      return;
    }

    final isDestination = _simulationIndex >= shipment.route.path.length - 1;
    final newPoint = shipment.route.path[_simulationIndex];

    // OPTIMISTIC UPDATE: Update local state immediately for smooth animation
    final updatedShipment = shipment.copyWith(
      currentLocation: newPoint,
      status: isDestination ? 'DELIVERED' : 'IN_TRANSIT',
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
        point: newPoint,
      );
      if (isDestination) {
        _stopSimulation();
      } else {
        final step = (shipment.route.path.length / 100).ceil();
        _simulationIndex += step <= 0 ? 1 : step;
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
    notifyListeners();
  }

  @override
  void dispose() {
    _activeShipmentSubscription?.cancel();
    _simulationTimer?.cancel();
    _systemCheckTimer?.cancel();
    super.dispose();
  }
}
