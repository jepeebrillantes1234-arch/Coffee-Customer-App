import 'package:flutter/material.dart';

/// Coffee, cream, and gold palette used by the Rider module.
const riderGreen = Color(0xFF176B67);
const riderCharcoal = Color(0xFF3A190A);
const riderTeal = Color(0xFF168A83);
const riderMutedTeal = Color(0xFFE3F1EF);
const riderCoffee = Color(0xFF4B210D);
const riderDeepCoffee = Color(0xFF2A1005);
const riderGold = Color(0xFFE8AF4B);
const riderCream = Color(0xFFFFF3E0);
const riderMutedBrown = Color(0xFF7A604D);

ThemeData riderThemeData(BuildContext context) {
  final base = Theme.of(context);
  final dark = base.brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF24160F) : const Color(0xFFFFFCF7);
  final raised = dark ? const Color(0xFF342319) : Colors.white;
  final scheme = base.colorScheme.copyWith(
    primary: dark ? riderGold : riderCoffee,
    onPrimary: dark ? riderDeepCoffee : Colors.white,
    secondary: riderGold,
    surface: surface,
    onSurface: dark ? const Color(0xFFFFF6EB) : const Color(0xFF2E1A10),
    surfaceContainerHighest: dark
        ? const Color(0xFF3A291E)
        : const Color(0xFFFFEBD0),
    outlineVariant: dark ? const Color(0xFF624B39) : const Color(0xFFE9D1AF),
  );

  return base.copyWith(
    colorScheme: scheme,
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    scaffoldBackgroundColor: dark ? const Color(0xFF1B100A) : riderCream,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: riderDeepCoffee,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: raised,
      elevation: dark ? 1 : 2,
      shadowColor: riderCoffee.withValues(alpha: .12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(19),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .75)),
      ),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: dark ? riderDeepCoffee : const Color(0xFFFFF9F0),
      indicatorColor: riderGold.withValues(alpha: dark ? .32 : .27),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? (dark ? riderGold : riderCoffee)
              : (dark ? Colors.white70 : riderMutedBrown),
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? (dark ? riderGold : riderCoffee)
              : (dark ? Colors.white70 : riderMutedBrown),
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    switchTheme: base.switchTheme.copyWith(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFF248A42)
            : null,
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: raised,
      labelStyle: TextStyle(color: dark ? riderGold : riderMutedBrown),
      hintStyle: TextStyle(
        color: dark ? const Color(0xFFBDAA98) : riderMutedBrown,
      ),
      prefixIconColor: dark ? riderGold : riderCoffee,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: riderGold, width: 1.6),
      ),
    ),
  );
}

class RiderVisualTheme extends StatelessWidget {
  const RiderVisualTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: riderThemeData(context), child: child);
}

/// Uses the supplied coffee artwork behind Rider content without covering it.
class RiderImageBackground extends StatelessWidget {
  const RiderImageBackground({
    super.key,
    required this.child,
    this.image = 'assets/images/all.png',
    this.alignment = Alignment.topCenter,
    this.enabled = true,
  });

  final Widget child;
  final String image;
  final Alignment alignment;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(image, fit: BoxFit.cover, alignment: alignment),
        ColoredBox(
          color: dark
              ? Colors.black.withValues(alpha: .68)
              : riderCream.withValues(alpha: .12),
        ),
        child,
      ],
    );
  }
}

Color riderAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? riderGold : riderCoffee;

Color riderPrimaryText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFF5E8)
    : const Color(0xFF2E1A10);

Color riderSecondaryText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFD8C3B0)
    : riderMutedBrown;

String deliveryStatusLabel(String s) {
  switch (s) {
    case 'assigned':
      return 'New assignment';
    case 'accepted':
      return 'Accepted';
    case 'picked_up':
      return 'Order picked up';
    case 'on_the_way':
      return 'On the way';
    case 'declined':
      return 'Declined';
    case 'delivered':
      return 'Delivered';
    default:
      return s;
  }
}

Color deliveryStatusColor(String s) {
  switch (s) {
    case 'assigned':
      return Colors.amber.shade800;
    case 'accepted':
      return const Color(0xFF426C7C);
    case 'declined':
      return Colors.red.shade700;
    case 'picked_up':
      return const Color(0xFF536D9A);
    case 'on_the_way':
      return const Color(0xFF176B67);
    case 'delivered':
      return const Color(0xFF3C8D5A);
    default:
      return Colors.grey;
  }
}
