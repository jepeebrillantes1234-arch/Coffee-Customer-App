import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/role_home.dart';
import 'register_screen.dart';
import 'customer_service_sheet.dart';

final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
Future<void>? _googleSignInInitialization;

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _hide = true;
  bool _remember = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _remember = p.getBool('remember_me') ?? true);
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.I.login(_username.text.trim(), _password.text);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', _remember);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => homeForRole(Api.I.role)),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final emailController = TextEditingController(
      text: _email.text.contains('@') ? _email.text.trim() : '',
    );
    var sending = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, dialogSetState) => AlertDialog(
          title: const Text('Reset your password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your account email and we will send a password reset link.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      final email = emailController.text.trim();
                      if (!email.contains('@')) {
                        dialogSetState(
                          () => error = 'Enter a valid email address.',
                        );
                        return;
                      }
                      dialogSetState(() {
                        sending = true;
                        error = null;
                      });
                      try {
                        await Api.I.forgotPassword(email);
                        if (!mounted || !ctx.mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'If that email is registered, a reset link has been sent.',
                            ),
                          ),
                        );
                      } on ApiException catch (e) {
                        if (ctx.mounted) {
                          dialogSetState(() {
                            sending = false;
                            error = e.message;
                          });
                        }
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send reset link'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (AppConfig.googleServerClientId.isEmpty) {
        throw ApiException(
          'Google sign-in needs a Web OAuth client ID. Configure GOOGLE_SERVER_CLIENT_ID and rebuild the app.',
        );
      }
      _googleSignInInitialization ??= _googleSignIn.initialize(
        serverClientId: AppConfig.googleServerClientId,
      );
      await _googleSignInInitialization;
      // GoogleSignIn v7 uses initialize() + authenticate(). The Google token
      // is exchanged with Firebase first; only the Firebase ID token goes to
      // Laravel, which verifies it with Firebase Admin.
      await _googleSignIn.signOut();
      final account = await _googleSignIn.authenticate();
      final googleIdToken = account.authentication.idToken;
      if (googleIdToken == null || googleIdToken.isEmpty) {
        throw ApiException('Google did not return a sign-in token.');
      }

      final credential = GoogleAuthProvider.credential(
        idToken: googleIdToken,
      );
      final firebaseCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final firebaseUser = firebaseCredential.user;
      if (firebaseUser == null) {
        throw ApiException('Firebase could not authenticate this Google account.');
      }
      final firebaseIdToken = await firebaseUser.getIdToken(true);
      if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
        throw ApiException('Firebase did not return a valid ID token.');
      }

      await Api.I.loginWithGoogle(firebaseIdToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => homeForRole(Api.I.role)),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on GoogleSignInException catch (e, stackTrace) {
      debugPrint('Google sign-in failed (${e.code.name}): ${e.description}');
      debugPrintStack(stackTrace: stackTrace);
      final message = switch (e.code) {
        GoogleSignInExceptionCode.canceled => 'Google sign-in was canceled.',
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Google sign-in configuration is incorrect. Check that the Firebase Android package name and SHA-1 match this app.',
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google sign-in is not configured or enabled in Firebase Authentication.',
        _ =>
          'Google sign-in failed (${e.code.name}): '
          '${e.description ?? 'Please try again.'}',
      };
      if (mounted) setState(() => _error = message);
    } on FirebaseAuthException catch (e, stackTrace) {
      debugPrint('Firebase Auth failed (${e.code}): ${e.message}');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(
          () => _error =
              'Firebase sign-in failed (${e.code}): '
              '${e.message ?? 'Please try again.'}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Unhandled Google sign-in failure: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'Google sign-in failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: c, width: w),
  );

  InputDecoration _dec(String hint, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
        suffixIcon: suffix,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: _border(Theme.of(context).colorScheme.outlineVariant),
        enabledBorder: _border(Theme.of(context).colorScheme.outlineVariant),
        focusedBorder: _border(Theme.of(context).colorScheme.primary, 1.5),
        errorBorder: _border(Colors.red.shade300),
        focusedErrorBorder: _border(Colors.red.shade400, 1.5),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---------- LOGO ----------
                    Center(
                      child: Image.asset(
                        'assets/images/logo1.png',
                        height: 104,
                        cacheHeight: 320,
                        errorBuilder: (_, e, s) => Icon(
                          Icons.local_cafe,
                          size: 72,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'KJM COFFEE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'COFFEE • JOY • MOMENTS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 3,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 30),

                    // ---------- TITLE ----------
                    Text(
                      'Welcome Back!',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Log in to continue your coffee journey.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 22),

                    // ---------- FIELDS ----------
                    TextFormField(
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: _dec('Username', Icons.alternate_email),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) {
                          return 'Please enter your username.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hide,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _busy ? null : _submit(),
                      decoration: _dec(
                        'Password',
                        Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _hide
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Please enter your password.';
                        }
                        return null;
                      },
                    ),

                    // ---------- REMEMBER ME / FORGOT ----------
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: Checkbox(
                                value: _remember,
                                activeColor: Theme.of(context).colorScheme.primary,
                                visualDensity: VisualDensity.compact,
                                onChanged: (v) =>
                                    setState(() => _remember = v ?? true),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Remember me',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _forgot,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot password?',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        onPressed: () => showCustomerServiceSheet(context),
                        icon: const Icon(Icons.support_agent_outlined, size: 19),
                        label: const Text('Contact Customer Service'),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 20),

                    // ---------- BUTTON ----------
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Log In',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),

                    // ---------- GOOGLE SIGN-IN ----------
                    const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'or',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _socialButton(
                        label: 'Continue with Google',
                        icon: Image.asset(
                          'assets/images/google.png',
                          width: 22,
                          height: 22,
                          errorBuilder: (_, _, _) => const Text(
                            'G',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                        ),
                        onTap: _busy ? () {} : _signInWithGoogle,
                      ),

                    // ---------- OPEN REGISTRATION ----------
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account?",
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  ),
                          child: Text(
                            'Sign up',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: Theme.of(context).colorScheme.surface,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 28, child: Center(child: icon)),
          const SizedBox(width: 12),
          Text(
            label,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
