import 'package:flutter/material.dart';

/// Neutral coffee-shop palette shared by the Rider module.
const riderGreen = Color(0xFF26734D);
const riderCharcoal = Color(0xFF292725);
const riderTeal = Color(0xFF176B67);
const riderMutedTeal = Color(0xFFEAF2EF);
const riderCoffee = Color(0xFF563927);
const riderMediumBrown = Color(0xFF765039);
const riderDeepCoffee = Color(0xFF402B20);
const riderGold = Color(0xFF9A6D36);
const riderCream = Color(0xFFF7F6F3);
const riderMutedBrown = Color(0xFF716A64);

ThemeData riderThemeData(BuildContext context) {
  final base = Theme.of(context);
  final dark = base.brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF211F1D) : const Color(0xFFF7F6F3);
  final raised = dark ? const Color(0xFF2B2926) : Colors.white;
  final scheme = base.colorScheme.copyWith(
    primary: dark ? const Color(0xFFD6B17A) : riderCoffee,
    onPrimary: dark ? const Color(0xFF241A13) : Colors.white,
    secondary: riderMutedBrown,
    surface: surface,
    onSurface: dark ? riderCream : const Color(0xFF35261D),
    surfaceContainerHighest: dark
        ? const Color(0xFF383532)
        : const Color(0xFFECEAE6),
    outlineVariant: dark ? const Color(0xFF494642) : const Color(0xFFE2E0DC),
  );

  return base.copyWith(
    colorScheme: scheme,
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    scaffoldBackgroundColor: surface,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: surface,
      foregroundColor: scheme.onSurface,
      iconTheme: IconThemeData(color: scheme.onSurface),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: raised,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: raised,
      indicatorColor: scheme.primary.withValues(alpha: dark ? .24 : .12),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : (dark ? Colors.white70 : riderMutedBrown),
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? riderCream : riderCoffee,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        borderSide: BorderSide(color: riderGold, width: 1.6),
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
    this.enabled = false,
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
              : riderCream.withValues(alpha: .32),
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
    ? riderCream
    : const Color(0xFF35261D);

Color riderSecondaryText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFD6C7B7)
    : riderMutedBrown;

class RiderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RiderAppBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.showBackButton = true,
    this.showLogo = false,
    this.onBack,
  });

  final String title;
  final List<Widget> actions;
  final bool showBackButton;
  final bool showLogo;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: Theme.of(context).colorScheme.surface,
    foregroundColor: Theme.of(context).colorScheme.onSurface,
    automaticallyImplyLeading: false,
    leadingWidth: (showLogo ? 58 : 0) + (showBackButton ? 48 : 0),
    leading: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLogo) ...[const SizedBox(width: 10), riderLogoBadge()],
        if (showBackButton)
          IconButton(
            tooltip: 'Back',
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
      ],
    ),
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    ),
    centerTitle: false,
    actions: actions,
  );
}

Widget riderLogoBadge() => Container(
  width: 40,
  height: 40,
  padding: const EdgeInsets.all(3),
  decoration: BoxDecoration(
    color: riderCream,
    borderRadius: BorderRadius.circular(11),
  ),
  child: Image.asset('assets/images/logo1.png', fit: BoxFit.contain),
);

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
