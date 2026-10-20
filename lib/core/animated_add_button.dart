import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Pindutan na "+" na may magandang animation kapag pinindot:
/// 1. lumiliit tapos tumatalbog (spring)
/// 2. may singsing na kumakalat at nawawala
/// 3. ang "+" ay pumipihit at nagiging berdeng "check", tapos bumabalik sa "+"
/// 4. may lumulutang na "+1" na tumataas at nawawala
///
/// Pareho ang gamit sa dati: AnimatedAddButton(onPressed: ..., size: 30)
class AnimatedAddButton extends StatefulWidget {
  const AnimatedAddButton({
    super.key,
    required this.onPressed,
    this.size = 30,
    this.label = '+1',
  });

  final VoidCallback onPressed;
  final double size;

  /// Ang text na lumulutang paitaas (hal. '+1'). Gawing '' kung ayaw mo.
  final String label;

  @override
  State<AnimatedAddButton> createState() => _AnimatedAddButtonState();
}

class _AnimatedAddButtonState extends State<AnimatedAddButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _down = false;

  late final Animation<double> _bounce = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.82).chain(CurveTween(curve: Curves.easeOut)), weight: 12),
    TweenSequenceItem(tween: Tween(begin: 0.82, end: 1.14).chain(CurveTween(curve: Curves.easeOutBack)), weight: 22),
    TweenSequenceItem(tween: Tween(begin: 1.14, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 16),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    // Iwasan ang aksidenteng double-tap sa pinakaunang bahagi ng animation
    if (_c.isAnimating && _c.value < 0.10) return;
    HapticFeedback.lightImpact();
    widget.onPressed(); // agad, para mabilis ang tugon
    _c.forward(from: 0);
  }

  /// Bahagi (0 hanggang 1) ng timeline sa pagitan ng [a] at [b]
  double _seg(double a, double b) {
    final t = (_c.value - a) / (b - a);
    return t < 0 ? 0 : (t > 1 ? 1 : t);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    return Semantics(
      button: true,
      label: 'Customize and add to cart',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: _tap,
        child: SizedBox(
          width: s,
          height: s,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final v = _c.value;
              final running = v > 0 && v < 1;

              // "check" sa gitna ng animation, "+" sa simula at dulo
              final showCheck = v >= 0.18 && v < 0.80;
              final success = _amount(); // 0 = kayumanggi, 1 = berde
              final color = Color.lerp(espresso, const Color(0xFF3C8D5A), success)!;

              // pihit ng "+" bago maging check, at pabalik pagkatapos
              double angle = 0;
              if (v < 0.18) {
                angle = Curves.easeOut.transform(_seg(0.0, 0.18)) * (math.pi / 2);
              } else if (v >= 0.80) {
                angle = (1 - Curves.easeOut.transform(_seg(0.80, 0.95))) * (-math.pi / 2);
              }

              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (running) _ring(s),
                  AnimatedScale(
                    scale: _down ? 0.9 : 1.0,
                    duration: const Duration(milliseconds: 90),
                    child: Transform.scale(
                      scale: _bounce.value,
                      child: Container(
                        width: s,
                        height: s,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.30 + 0.20 * success),
                              blurRadius: 6 + 8 * success,
                              offset: Offset(0, 2 + 2 * success),
                            ),
                          ],
                        ),
                        child: Transform.rotate(
                          angle: angle,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim,
                              child: FadeTransition(opacity: anim, child: child),
                            ),
                            child: Icon(
                              showCheck ? Icons.check_rounded : Icons.add_rounded,
                              key: ValueKey(showCheck),
                              size: s * 0.62,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (running && widget.label.isNotEmpty) _floatingLabel(s),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Gaano na kaberde ang pindutan (pataas sa simula, pababa sa dulo)
  double _amount() => _seg(0.12, 0.28) - _seg(0.78, 0.92);

  /// Singsing na kumakalat at nawawala
  Widget _ring(double s) {
    final t = Curves.easeOut.transform(_seg(0.08, 0.60));
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final size = s * (1.0 + 0.9 * t);
    return IgnorePointer(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Opacity(
          opacity: (1 - t) * 0.55,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF3C8D5A), width: 2),
            ),
          ),
        ),
      ),
    );
  }

  /// "+1" na lumulutang paitaas at nawawala
  Widget _floatingLabel(double s) {
    final t = _seg(0.14, 0.90);
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final rise = Curves.easeOut.transform(t) * s * 1.5;
    final opacity = t < 0.2 ? t / 0.2 : 1 - ((t - 0.2) / 0.8);
    return IgnorePointer(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: Transform.translate(
          offset: Offset(0, -s * 0.9 - rise),
          child: Opacity(
            opacity: opacity < 0 ? 0 : (opacity > 1 ? 1 : opacity),
            child: Text(
              widget.label,
              style: const TextStyle(
                color: Color(0xFF3C8D5A),
                fontSize: 15,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Colors.white, blurRadius: 4)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}