import 'package:flutter/widgets.dart';

import '../rider/rider_home_screen.dart';
import '../screens/root_screen.dart';

/// Isang app, dalawang UI: Rider -> berdeng Rider mode, Customer -> Customer app
Widget homeForRole(String? role) =>
    role == 'rider' ? const RiderHomeScreen() : const RootScreen();
