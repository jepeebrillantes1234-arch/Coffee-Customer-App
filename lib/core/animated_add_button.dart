import 'package:flutter/material.dart';
import 'theme.dart';

class AnimatedAddButton extends StatefulWidget {
  const AnimatedAddButton({super.key, required this.onPressed, this.size = 30});

  final VoidCallback onPressed;
  final double size;

  @override
  State<AnimatedAddButton> createState() => _AnimatedAddButtonState();
}

class _AnimatedAddButtonState extends State<AnimatedAddButton>
    with SingleTickerProviderStateMixin {
  bool _animating = false;

  Future<void> _tap() async {
    if (_animating) return;
    setState(() => _animating = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _animating = false);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Customize and add to cart',
      child: GestureDetector(
        onTap: _tap,
        child: AnimatedScale(
          scale: _animating ? 0.88 : 1.0, // Modern tactile press-down effect
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeInOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: espresso,
              shape: BoxShape.circle,
              // Modern 2026 soft glowing shadow style
              boxShadow: [
                BoxShadow(
                  color: espresso.withOpacity(_animating ? 0.4 : 0.2),
                  blurRadius: _animating ? 12 : 6,
                  offset: Offset(0, _animating ? 4 : 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: AnimatedRotation(
              turns: _animating ? 0.25 : 0, // Smooth 90-degree twist
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  _animating ? Icons.check_rounded : Icons.add_rounded,
                  key: ValueKey(_animating),
                  size: widget.size * 0.6,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}