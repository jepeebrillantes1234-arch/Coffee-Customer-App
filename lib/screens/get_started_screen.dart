import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'register_screen.dart';

class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({super.key});

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const _slides = <_WelcomeSlide>[
    _WelcomeSlide(
      image: 'assets/images/getstarted2.png',
      title: 'A Better Cup, Every Day',
      description:
          'Enjoy freshly brewed coffee and your favorite drinks, made just the way you like them.',
    ),
    _WelcomeSlide(
      image: 'assets/images/getstarted1.png',
      title: 'Made with Care',
      description:
          'Our baristas craft every cup with care, quality ingredients, and a little KJM magic.',
    ),
    _WelcomeSlide(
      image: 'assets/images/getstarted.png',
      title: 'Your Coffee, Your Moment',
      description:
          'Find your favorites, place an order, and make every coffee break a good one.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openAuth(BuildContext context, {required bool register}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => register ? const RegisterScreen() : const AuthScreen(),
    ));
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _slides.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _continue() {
    if (_page < _slides.length - 1) {
      _goToPage(_page + 1);
    } else {
      _openAuth(context, register: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).height < 720;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, isCompact ? 8 : 16, 24, 12),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _goToPage(_slides.length - 1),
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                flex: 6,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Image.asset(
                        slide.image,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.coffee_rounded,
                          size: 120,
                          color: colors.primary.withValues(alpha: .55),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: isCompact ? 10 : 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Column(
                  key: ValueKey(_page),
                  children: [
                    Text(
                      _slides[_page].title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: isCompact ? 24 : 28,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _slides[_page].description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isCompact ? 16 : 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (index) {
                  final selected = index == _page;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Semantics(
                      button: true,
                      label: 'Go to introduction page ${index + 1}',
                      selected: selected,
                      child: InkWell(
                        onTap: () => _goToPage(index),
                        customBorder: const StadiumBorder(),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: selected ? 26 : 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: selected
                                ? colors.primary
                                : colors.outlineVariant,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              SizedBox(height: isCompact ? 18 : 26),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _continue,
                  child: Text(
                    _page == _slides.length - 1 ? 'Get Started' : 'Next',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Already have an account?  ',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  TextButton(
                    onPressed: () => _openAuth(context, register: false),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: const Text(
                      'Log in',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeSlide {
  const _WelcomeSlide({
    required this.image,
    required this.title,
    required this.description,
  });

  final String image;
  final String title;
  final String description;
}
