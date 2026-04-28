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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (DashboardFirebaseOptions.enabled) {
    await Firebase.initializeApp(
      options: DashboardFirebaseOptions.currentPlatform,
    );
  }

  final apiService = ApiService();
  final firebaseService = FirebaseService();
  final aiService = AiService(apiService);
  final locationService = LocationService(apiService);

  runApp(
    MultiProvider(
      providers: [
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
}

class LogisticsDashboardApp extends StatelessWidget {
  const LogisticsDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Logistics',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainNavigationWrapper(),
    );
  }
}
