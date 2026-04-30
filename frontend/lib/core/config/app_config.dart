import 'package:flutter/foundation.dart';
import '../utils/time_utils.dart';

class AppConfig {
  static String get apiBaseUrl {
    const url = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api-gateway-835572562592.us-central1.run.app/',
    );

    // Automatically handle Android emulator bridge if using default localhost
    if (url == 'http://localhost:5000' &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return url;
  }

  static const String initialShipmentId = String.fromEnvironment(
    'SHIPMENT_ID',
    defaultValue: '',
  );

  static const bool enableSimulationControls = bool.fromEnvironment(
    'ENABLE_SIMULATION_CONTROLS',
    defaultValue: true,
  );

  static const int backendPollIntervalSeconds = int.fromEnvironment(
    'BACKEND_POLL_INTERVAL_SECONDS',
    defaultValue: 5,
  );

  static const int simulationStepIntervalSeconds = int.fromEnvironment(
    'SIMULATION_STEP_INTERVAL_SECONDS',
    defaultValue: 2,
  );

  static Duration get backendPollInterval =>
      durationFromSeconds(backendPollIntervalSeconds);

  static Duration get simulationStepInterval =>
      durationFromSeconds(simulationStepIntervalSeconds);
}
