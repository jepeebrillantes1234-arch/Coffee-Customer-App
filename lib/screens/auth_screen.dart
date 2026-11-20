import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/error_ui.dart';
import '../core/role_home.dart';
import 'register_screen.dart';
import 'customer_service_sheet.dart';
import 'forgot_password_screen.dart';

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
  int? _errorStatusCode;
  bool _showRequestRecovery = false;
  VoidCallback? _retryAction;
  Timer? _lockoutTimer;
  int _lockoutRemainingSeconds = 0;
  bool _passwordResetRequired = false;

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
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _lockoutRemainingSeconds > 0 || _passwordResetRequired) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _errorStatusCode = null;
      _showRequestRecovery = false;
      _retryAction = null;
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
      if (mounted) {
        setState(() {
          _error = e.displayMessage;
          _errorStatusCode = e.statusCode;
          _showRequestRecovery =
              e.securityStatus == null && _shouldShowRequestRecovery(e);
          _retryAction = _showRequestRecovery ? _submit : null;
          _applySecurityState(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _email.text.contains('@') ? _email.text.trim() : '',
        ),
      ),
    );
    if (!mounted) return;
    _lockoutTimer?.cancel();
    setState(() {
      // The backend remains authoritative if the user returned without
      // completing the reset; it will send the forced-reset response again.
      _passwordResetRequired = false;
      _lockoutRemainingSeconds = 0;
      _error = null;
      _errorStatusCode = null;
      _showRequestRecovery = false;
      _retryAction = null;
    });
  }

  Future<void> _signInWithGoogle() async {
    if (_busy || _lockoutRemainingSeconds > 0 || _passwordResetRequired) return;
    var backendRequestStarted = false;
    setState(() {
      _busy = true;
      _error = null;
      _errorStatusCode = null;
      _showRequestRecovery = false;
      _retryAction = null;
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

      final credential = GoogleAuthProvider.credential(idToken: googleIdToken);
      final firebaseCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final firebaseUser = firebaseCredential.user;
      if (firebaseUser == null) {
        throw ApiException(
          'Firebase could not authenticate this Google account.',
        );
      }
      final firebaseIdToken = await firebaseUser.getIdToken(true);
      if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
        throw ApiException('Firebase did not return a valid ID token.');
      }

      backendRequestStarted = true;
      await Api.I.loginWithGoogle(firebaseIdToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => homeForRole(Api.I.role)),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.displayMessage;
          _errorStatusCode = e.statusCode;
          _showRequestRecovery =
              backendRequestStarted &&
              e.securityStatus == null &&
              _shouldShowRequestRecovery(e);
          _retryAction = _showRequestRecovery ? _signInWithGoogle : null;
          _applySecurityState(e);
        });
      }
    } on GoogleSignInException catch (e, stackTrace) {
      debugPrint('Google sign-in failed (${e.code.name}): ${e.description}');
      debugPrintStack(stackTrace: stackTrace);
      final message = switch (e.code) {
        GoogleSignInExceptionCode.canceled => 'Google sign-in was canceled.',
        GoogleSignInExceptionCode.clientConfigurationError => 'Google sign-in configuration is incorrect. Check that the Firebase Android package name and SHA-1 match this app.',
        GoogleSignInExceptionCode.providerConfigurationError => 'Google sign-in is not configured or enabled in Firebase Authentication.',
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
      debugPrint('Unhandled Google sign-in failure (${e.runtimeType}).');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(
          () => _error =
              'Google sign-in could not be completed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applySecurityState(ApiException error) {
    _lockoutTimer?.cancel();
    _passwordResetRequired = error.passwordResetRequired;
    _lockoutRemainingSeconds = error.passwordResetRequired
        ? 0
        : (error.securityStatus == 'locked'
              ? (error.retryAfterSeconds ?? 0).clamp(0, 300).toInt()
              : 0);
    if (_lockoutRemainingSeconds <= 0) return;

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _lockoutRemainingSeconds = (_lockoutRemainingSeconds - 1)
            .clamp(0, 300)
            .toInt();
        if (_lockoutRemainingSeconds == 0) timer.cancel();
      });
    });
  }

  String get _lockoutCountdown {
    final minutes = (_lockoutRemainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_lockoutRemainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  OutlineInputBorder _border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: c, width: w),
  );

  InputDecoration _dec(String hint, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
                              activeColor: Theme.of(context)
                                  .colorScheme
                                  .primary,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                        icon: const Icon(
                          Icons.support_agent_outlined,
                          size: 19,
                        ),
                        label: const Text('Contact Customer Service'),
                      ),
                    ),

                    if (_error != null && _showRequestRecovery) ...[
                      const SizedBox(height: 12),
                      KjmErrorNotice(
                        message: _error!,
                        statusCode: _errorStatusCode,
                        onRetry: _retryAction ?? _submit,
                      ),
                    ] else if (_error != null) ...[
                      const SizedBox(height: 12),
                      KjmInlineError(message: _error!),
                    ],
                    if (_lockoutRemainingSeconds > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Login is temporarily locked. You can try again in $_lockoutCountdown.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (_passwordResetRequired) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Reset your password to restore access to this account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _forgot,
                        icon: const Icon(Icons.lock_reset_rounded),
                        label: const Text('Reset password'),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // ---------- BUTTON ----------
                    FilledButton(
                      onPressed:
                          _busy ||
                              _lockoutRemainingSeconds > 0 ||
                              _passwordResetRequired
                          ? null
                          : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _busy
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
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
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
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
                      onTap:
                          _busy ||
                              _lockoutRemainingSeconds > 0 ||
                              _passwordResetRequired
                          ? () {}
                          : _signInWithGoogle,
                    ),

                    // ---------- OPEN REGISTRATION ----------
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account?",
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
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

bool _shouldShowRequestRecovery(ApiException error) {
  final status = error.statusCode;
  if (status == null) return true;
  return status == 404 ||
      status == 408 ||
      status == 419 ||
      status == 429 ||
      status == 500 ||
      status == 502 ||
      status == 503 ||
      status == 504;
}
