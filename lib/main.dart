import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'core/api.dart';
import 'core/config.dart';
import 'core/http_402_warning.dart';
import 'core/push_notifications.dart';
import 'core/role_home.dart';
import 'core/theme.dart';
import 'screens/get_started_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/support_chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await Api.I.init();
  Api.I.onHttp402 = (retryRequest, serverMessage) => Http402Warning.show(
    navigatorKey: PushNotifications.navigatorKey,
    productionWebsite: AppConfig.productionWebsiteUri,
    retryRequest: retryRequest,
    serverMessage: serverMessage,
    onContactAdministrator: () {
      PushNotifications.navigatorKey.currentState?.push<void>(
        MaterialPageRoute<void>(builder: (_) => const SupportChatScreen()),
      );
    },
  );
  await AppThemeController.I.load();
  runApp(const KjmApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(PushNotifications.I.initialize());
  });
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
        navigatorKey: PushNotifications.navigatorKey,
        scaffoldMessengerKey: PushNotifications.messengerKey,
        themeMode: AppThemeController.I.mode,
        theme: appTheme(ThemeMode.light),
        darkTheme: appTheme(ThemeMode.dark),
        home: SplashScreen(
          nextScreen: Api.I.loggedIn
              ? homeForRole(Api.I.role)
              : const GetStartedScreen(),
          onCompleted: PushNotifications.I.markNavigationReady,
        ),
      ),
    );
  }
}
