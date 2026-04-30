import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/dashboard_controller.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'modules/main_navigation_wrapper.dart';
import 'services/ai_service.dart';
import 'services/api_service.dart';
import 'services/firebase_service.dart';
import 'services/location_service.dart';
import 'services/auth_service.dart';
import 'controllers/auth_controller.dart';
import 'modules/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error handler for better debugging in Web
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FLUTTER ERROR: ${details.exception}');
  };

  try {

  if (DashboardFirebaseOptions.enabled) {
    await Firebase.initializeApp(
      options: DashboardFirebaseOptions.currentPlatform,
    );
  }

  final authService = AuthService();
  final apiService = ApiService(getToken: authService.getIdToken);
  final firebaseService = FirebaseService();
  final aiService = AiService(apiService);
  final locationService = LocationService(apiService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthController(authService: authService),
        ),
        ChangeNotifierProvider(
          create: (_) => DashboardController(
            apiService: apiService,
            firebaseService: firebaseService,
            aiService: aiService,
            locationService: locationService,
          )..bootstrap(),
        ),
      ],
      child: const LogisticsDashboardApp(),
    ),
  );
  } catch (e, stack) {
    debugPrint('FATAL INITIALIZATION ERROR: $e');
    debugPrint(stack.toString());
  }
}

class LogisticsDashboardApp extends StatelessWidget {
  const LogisticsDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Logistics',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();

    if (authController.isAuthenticated) {
      return const MainNavigationWrapper();
    } else {
      return const LoginScreen();
    }
  }
}
