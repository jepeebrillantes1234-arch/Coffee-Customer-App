import 'package:flutter/material.dart';

import 'auth_screen.dart';
import 'register_screen.dart';

class GetStartedScreen extends StatelessWidget {
  const GetStartedScreen({super.key});


  void _openAuth(BuildContext context, {required bool register}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => register ? const RegisterScreen() : const AuthScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 18, 28, 20),
                child: Column(
                  children: [
                    SizedBox(height: height < 740 ? 18 : 28),
                    Text('Great Coffee\nfor Every Moment', textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, height: 1.12, fontSize: 29, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text('Freshly brewed, crafted with passion.', textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15)),
                    SizedBox(height: height < 740 ? 12 : 22),
                    SizedBox(height: height < 740 ? 230 : 300, width: double.infinity,
                      child: Image.asset('assets/images/getstarted.png', fit: BoxFit.contain)),
                    const SizedBox(height: 8),
                    Text('Great Coffee\nfor Every Moment', textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, height: 1.12, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('Freshly brewed, crafted with passion.', textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
                    const SizedBox(height: 22),
                    const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _PageDot(active: true), SizedBox(width: 12), _PageDot(), SizedBox(width: 12), _PageDot(),
                    ]),
                    const SizedBox(height: 24),
                    SizedBox(width: double.infinity, height: 58,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                        onPressed: () => _openAuth(context, register: true),
                        child: const Text('Get Started', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      )),
                    const SizedBox(height: 18),
                    Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('Already have an account?  ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      TextButton(
                        onPressed: () => _openAuth(context, register: false),
                        style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary, padding: const EdgeInsets.symmetric(horizontal: 4)),
                        child: const Text('Log in', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDot extends StatelessWidget {
  const _PageDot({this.active = false});
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    width: active ? 10 : 8,
    height: active ? 10 : 8,
    decoration: BoxDecoration(
      color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
      shape: BoxShape.circle,
    ),
  );
}

