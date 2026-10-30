import 'package:flutter/material.dart';

/// KJM Coffee Splash Screen.
/// - Spinning and zooming in logo with expanding rings and glow effect
/// - Letters K, J, M appearing one by one
/// - Visible loading bar with percentage, status message, and moving coffee cup icon
/// - Unchanged usage: SplashScreen(nextScreen: ...)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.nextScreen});

  final Widget nextScreen;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Total duration of the splash. Adjust as needed.
  static const _duration = Duration(milliseconds: 3600);

  static const _gold = Color(0xFFFFFFFF);
  static const _caramel = Color(0xFFFFFFFF);
  static const _cream = Color(0xFFFFFFFF);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _duration,
  );
  Future<void>? _precache;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _goNext();
    });
    _c.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precache images during loading to prevent flickering on Home
    _precache ??= Future.wait([
      for (final p in const [
        'assets/images/logo1.png',
        'assets/images/coffee.png',
        'assets/images/coffee1.png',
        'assets/images/splash.png',
      ])
        precacheImage(AssetImage(p), context).catchError((_) {}),
    ]).then((_) {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    if (_leaving) return;
    _leaving = true;
    await _precache;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, _, _) => widget.nextScreen,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // ---------- HELPERS ----------
  /// Value (0 to 1) of an animation segment between [a] and [b]
  double _t(double a, double b, [Curve curve = Curves.easeOut]) =>
      Interval(a, b, curve: curve).transform(_c.value);

  double _c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  // ---------- BUILD ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/splash.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF111111)),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x55000000), Color(0xCC000000)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 30),
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) => Column(
                  children: [
                    const SizedBox(height: 28),
                    _logo(),
                    const SizedBox(height: 6),
                    _brand(),
                    const SizedBox(height: 8),
                    _subtitle(),
                    const SizedBox(height: 20),
                    _tagline(),
                    const Spacer(),
                    _loader(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- LOGO ----------
  Widget _logo() {
    final fade = _c01(_t(0.0, 0.28, Curves.easeIn));
    final scale = 0.25 + 0.75 * _t(0.0, 0.5, Curves.elasticOut);
    final turn = (1 - _t(0.0, 0.5, Curves.easeOutCubic)) * -0.8;

    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(0.10, 0.58),
          _ring(0.26, 0.74),
          // Glow behind the logo
          Opacity(
            opacity: fade,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [_gold.withValues(alpha: 0.18), Colors.transparent],
                ),
              ),
            ),
          ),
          Opacity(
            opacity: fade,
            child: Transform.rotate(
              angle: turn,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 114,
                  height: 114,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withValues(alpha: 0.55),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo1.png',
                      fit: BoxFit.cover,
                      cacheWidth: 360,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.coffee, size: 60, color: _caramel),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Expanding and fading ring
  Widget _ring(double a, double b) {
    final t = _t(a, b, Curves.easeOut);
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final size = 112 + 88 * t;
    return Opacity(
      opacity: _c01((1 - t) * 0.7),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _gold, width: 2),
        ),
      ),
    );
  }

  // ---------- BRAND ----------
  Widget _brand() {
    const letters = ['K', 'J', 'M'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < letters.length; i++)
          _letter(
            letters[i],
            _t(0.28 + i * 0.07, 0.50 + i * 0.07, Curves.easeOutBack),
          ),
      ],
    );
  }

  Widget _letter(String ch, double t) {
    return Opacity(
      opacity: _c01(t),
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 24),
        child: Text(
          ch,
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 50,
            fontWeight: FontWeight.bold,
            color: _cream,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }

  Widget _subtitle() {
    final t = _c01(_t(0.52, 0.74));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 30 * t, height: 1.8, color: _gold),
        Opacity(
          opacity: t,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'COFFEE SHOP',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _gold,
                letterSpacing: 3.5,
              ),
            ),
          ),
        ),
        Container(width: 30 * t, height: 1.8, color: _gold),
      ],
    );
  }

  Widget _tagline() {
    final t = _c01(_t(0.66, 0.88));
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 12),
        child: const Text(
          'Good Coffee\nBetter Days',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            color: Color(0xFFF5F5F5),
            height: 1.3,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  // ---------- LOADING BAR ----------
  Widget _loader() {
    final show = _c01(_t(0.34, 0.50));
    final p = _c01(_t(0.42, 1.0, Curves.easeInOutCubic));
    final percent = (p * 100).round();

    final msg = p < 0.30
        ? 'Brewing coffee...'
        : p < 0.65
        ? 'Fetching menu...'
        : p < 0.97
        ? 'Almost done...'
        : 'Ready!';

    return Opacity(
      opacity: show,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    msg,
                    style: TextStyle(
                      fontSize: 13,
                      color: _gold.withValues(alpha: 0.95),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _cream,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (_, box) {
                final w = box.maxWidth;
                final tipLeft = (w * p - 14) < 0
                    ? 0.0
                    : ((w * p - 14) > w - 28 ? w - 28 : (w * p - 14));
                return SizedBox(
                  height: 30,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      // Background of the bar
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      // Fill of the bar
                      Container(
                        height: 10,
                        width: w * p,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_gold, _caramel],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: _caramel.withValues(alpha: 0.65),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                      // Coffee cup moving along the bar
                      Positioned(
                        left: tipLeft,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: _caramel, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.coffee,
                            size: 15,
                            color: Color(0xFF111111),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
