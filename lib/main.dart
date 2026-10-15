import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/api.dart';
import 'core/role_home.dart';
import 'core/theme.dart';
import 'screens/get_started_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Api.I.init();
  await AppThemeController.I.load();
  runApp(const KjmApp());
}

class KjmApp extends StatelessWidget {
  const KjmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.I,
      builder: (context, _) => MaterialApp(
        title: 'KJM Coffee Brew',
        debugShowCheckedModeBanner: false,
        themeMode: AppThemeController.I.mode,
        theme: appTheme(ThemeMode.light),
        darkTheme: appTheme(ThemeMode.dark),
        home: SplashScreen(
          nextScreen: Api.I.loggedIn
              ? homeForRole(Api.I.role)
              : const GetStartedScreen(),
        ),
      ),
    );
  }
}


