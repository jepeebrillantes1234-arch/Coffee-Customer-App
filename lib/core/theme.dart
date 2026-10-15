import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const espresso = Color(0xFF4B2E2B);
const cream = Color(0xFFFFFFFF);
const caramel = Color(0xFFC8843C);
const success = Color(0xFF3C8D5A);

ThemeData appTheme([ThemeMode mode = ThemeMode.light]) {
  final dark = mode == ThemeMode.dark;
  final scheme = dark
      ? const ColorScheme.dark(
          primary: Color(0xFFE2B27D),
          onPrimary: Color(0xFF2A170D),
          secondary: Color(0xFFD39B62),
          onSecondary: Color(0xFF26170E),
          surface: Color(0xFF211B17),
          onSurface: Color(0xFFF5EEE7),
          error: Color(0xFFFFB4AB),
          onError: Color(0xFF690005),
        )
      : ColorScheme.fromSeed(seedColor: espresso, primary: espresso, secondary: caramel);
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF171311) : const Color(0xFFFFFCF7),
    canvasColor: dark ? const Color(0xFF171311) : const Color(0xFFFFFCF7),
    dividerColor: dark ? const Color(0xFF40362F) : const Color(0xFFECE4DC),
    textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light).textTheme.apply(
      bodyColor: dark ? const Color(0xFFF5EEE7) : const Color(0xFF241914),
      displayColor: dark ? const Color(0xFFF5EEE7) : const Color(0xFF241914),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF241E1A) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: dark ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF211B17) : Colors.white,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF2A231E) : Colors.white,
      hintStyle: TextStyle(color: dark ? const Color(0xFFB8AAA0) : const Color(0xFF8A7F7A)),
      labelStyle: TextStyle(color: dark ? const Color(0xFFD2C5BA) : const Color(0xFF62534A)),
      prefixIconColor: scheme.primary,
      suffixIconColor: scheme.onSurfaceVariant,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: dark ? const Color(0xFF51453C) : const Color(0xFFE8DED5))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: dark ? const Color(0xFF51453C) : const Color(0xFFE8DED5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: dark ? const Color(0xFF241E1A) : Colors.white, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: dark ? const Color(0xFF241E1A) : Colors.white, surfaceTintColor: Colors.transparent),
    snackBarTheme: SnackBarThemeData(backgroundColor: dark ? const Color(0xFF39302A) : const Color(0xFF33231B), contentTextStyle: const TextStyle(color: Colors.white)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: scheme.primary)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}

class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController I = AppThemeController._();
  static const _preferenceKey = 'app_theme_mode';
  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = prefs.getString(_preferenceKey) == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}

String statusLabel(String s, [String type = 'delivery']) {
  switch (s) {
    case 'awaiting_payment':
      return 'Awaiting payment';
    case 'pending':
      return 'Awaiting confirmation';
    case 'confirmed':
      return 'Confirmed by shop';
    case 'preparing':
      return 'Preparing your order';
    case 'ready':
      return type == 'pickup'
          ? 'Ready for pickup'
          : 'Ready, waiting for a rider';
    case 'rider_assigned':
      return 'Rider assigned';
    case 'picked_up':
      return 'Picked up by rider';
    case 'on_the_way':
      return 'On the way';
    case 'delivered':
      return 'Delivered';
    case 'completed':
      return 'Completed';
    case 'rejected':
      return 'Declined by shop';
    case 'cancelled':
      return 'Cancelled';
    default:
      return s;
  }
}

Color statusColor(String s) {
  switch (s) {
    case 'awaiting_payment':
    case 'pending':
      return Colors.amber.shade800;
    case 'confirmed':
    case 'preparing':
      return Colors.orange.shade800;
    case 'ready':
    case 'rider_assigned':
    case 'picked_up':
      return Colors.indigo;
    case 'on_the_way':
      return Colors.purple;
    case 'delivered':
    case 'completed':
      return success;
    default:
      return Colors.red.shade700;
  }
}
