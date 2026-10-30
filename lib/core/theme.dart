import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const espresso = Color(0xFF222222);
const cream = Color(0xFFF5F5F5);
const caramel = Color(0xFF111111);
const success = Color(0xFF3C8D5A);

ThemeData appTheme([ThemeMode mode = ThemeMode.light]) {
  final dark = mode == ThemeMode.dark;
  final scheme = dark
      ? const ColorScheme.dark(
          primary: Color(0xFFFFFFFF),
          onPrimary: Color(0xFF111111),
          secondary: Color(0xFFF5F5F5),
          onSecondary: Color(0xFF111111),
          primaryContainer: Color(0xFF383838),
          onPrimaryContainer: Color(0xFFF5F5F5),
          secondaryContainer: Color(0xFF2B2B2B),
          onSecondaryContainer: Color(0xFFF5F5F5),
          tertiaryContainer: Color(0xFF3B3320),
          onTertiaryContainer: Color(0xFFFFE7A3),
          surface: Color(0xFF1E1E1E),
          surfaceContainerLowest: Color(0xFF0D0D0D),
          surfaceContainerLow: Color(0xFF1E1E1E),
          surfaceContainer: Color(0xFF242424),
          surfaceContainerHigh: Color(0xFF2B2B2B),
          surfaceContainerHighest: Color(0xFF333333),
          onSurface: Color(0xFFF5F5F5),
          onSurfaceVariant: Color(0xFFAAAAAA),
          outline: Color(0xFF777777),
          outlineVariant: Color(0xFF383838),
          error: Color(0xFFFFB4AB),
          onError: Color(0xFF690005),
        )
      : const ColorScheme.light(
          primary: Color(0xFF111111),
          onPrimary: Color(0xFFFFFFFF),
          secondary: Color(0xFF222222),
          onSecondary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFFE5E5E5),
          onPrimaryContainer: Color(0xFF222222),
          secondaryContainer: Color(0xFFF0F0F0),
          onSecondaryContainer: Color(0xFF222222),
          tertiaryContainer: Color(0xFFFFF1CC),
          onTertiaryContainer: Color(0xFF5C4300),
          surface: Color(0xFFFFFFFF),
          surfaceContainerLowest: Color(0xFFFFFFFF),
          surfaceContainerLow: Color(0xFFFFFFFF),
          surfaceContainer: Color(0xFFF5F5F5),
          surfaceContainerHigh: Color(0xFFEEEEEE),
          surfaceContainerHighest: Color(0xFFE5E5E5),
          onSurface: Color(0xFF222222),
          onSurfaceVariant: Color(0xFF777777),
          outline: Color(0xFF777777),
          outlineVariant: Color(0xFFE5E5E5),
          error: Color(0xFFB3261E),
          onError: Color(0xFFFFFFFF),
        );
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF121212)
        : const Color(0xFFF5F5F5),
    canvasColor: dark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
    dividerColor: dark ? const Color(0xFF383838) : const Color(0xFFE5E5E5),
    textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
        .textTheme
        .apply(
          bodyColor: dark ? const Color(0xFFF5F5F5) : const Color(0xFF222222),
          displayColor: dark
              ? const Color(0xFFF5F5F5)
              : const Color(0xFF222222),
        ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
      hintStyle: TextStyle(
        color: dark ? const Color(0xFFAAAAAA) : const Color(0xFF777777),
      ),
      labelStyle: TextStyle(
        color: dark ? const Color(0xFFCCCCCC) : const Color(0xFF555555),
      ),
      prefixIconColor: scheme.primary,
      suffixIconColor: scheme.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: dark ? const Color(0xFF383838) : const Color(0xFFE5E5E5),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: dark ? const Color(0xFF383838) : const Color(0xFFE5E5E5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFF383838) : const Color(0xFF222222),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: scheme.primary),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant;
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected) ? scheme.primary : null;
      }),
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      side: BorderSide(color: scheme.onSurfaceVariant),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) return scheme.onPrimary;
        return scheme.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary.withValues(alpha: .7);
        }
        return scheme.surfaceContainerHighest;
      }),
    ),
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
    await prefs.setString(
      _preferenceKey,
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
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
