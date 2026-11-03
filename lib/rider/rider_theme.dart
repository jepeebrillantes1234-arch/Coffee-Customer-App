import 'package:flutter/material.dart';

/// Coffee, cream, and gold palette used by the Rider module.
const riderGreen = Color(0xFF176B67);
const riderCharcoal = Color(0xFF3A3028);
const riderTeal = Color(0xFF168A83);
const riderMutedTeal = Color(0xFFE3F1EF);
const riderCoffee = Color(0xFF5A3828);
const riderMediumBrown = Color(0xFF765039);
const riderDeepCoffee = Color(0xFF402B20);
const riderGold = Color(0xFFB58A55);
const riderCream = Color(0xFFF5EBDD);
const riderMutedBrown = Color(0xFF765039);

ThemeData riderThemeData(BuildContext context) {
  final base = Theme.of(context);
  final dark = base.brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF241E19) : const Color(0xFFFFFCF7);
  final raised = dark ? const Color(0xFF302720) : Colors.white;
  final scheme = base.colorScheme.copyWith(
    primary: dark ? riderGold : riderCoffee,
    onPrimary: dark ? const Color(0xFF241A13) : Colors.white,
    secondary: riderMediumBrown,
    surface: surface,
    onSurface: dark ? riderCream : const Color(0xFF35261D),
    surfaceContainerHighest: dark
        ? const Color(0xFF3A3028)
        : const Color(0xFFEDE1D1),
    outlineVariant: dark ? const Color(0xFF5E4C3F) : const Color(0xFFE2D3C1),
  );

  return base.copyWith(
    colorScheme: scheme,
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    scaffoldBackgroundColor: dark ? const Color(0xFF1C1713) : riderCream,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: riderCoffee,
      foregroundColor: riderCream,
      iconTheme: const IconThemeData(color: riderCream),
      titleTextStyle: const TextStyle(
        color: riderCream,
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
      backgroundColor: dark ? riderCoffee : const Color(0xFFF0E5D6),
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
    this.onBack,
  });

  final String title;
  final List<Widget> actions;
  final bool showBackButton;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: riderCoffee,
    foregroundColor: riderCream,
    automaticallyImplyLeading: false,
    leadingWidth: showBackButton ? 104 : 60,
    leading: Row(
      children: [
        const SizedBox(width: 10),
        riderLogoBadge(),
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
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: riderCream, fontWeight: FontWeight.w800),
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
