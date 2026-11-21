import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/error_ui.dart';
import '../core/role_home.dart';
import 'register_screen.dart';
import 'customer_service_sheet.dart';
import 'forgot_password_screen.dart';
import 'facebook_email_verification_screen.dart';

final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
Future<void>? _googleSignInInitialization;

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.initialLockout,
    this.facebookSignInForTesting,
    this.facebookLoginResultForTesting,
  });

  final LoginLockoutState? initialLockout;
  final Future<void> Function()? facebookSignInForTesting;
  final Future<LoginResult> Function()? facebookLoginResultForTesting;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _lockoutDialogKey = GlobalKey<_AccountLockoutDialogState>();
  final _username = TextEditingController();
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
  DateTime? _lockoutExpiresAt;
  bool _passwordResetRequired = false;
  bool _lockoutDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _remember = p.getBool('remember_me') ?? true);
    });
    final initialLockout = widget.initialLockout;
    if (initialLockout != null) {
      _activateLockout(initialLockout, showDialog: true);
      unawaited(_refreshLockoutFromServer(initialLockout.identifier));
    } else {
      Api.I.restoreLoginLockout().then((state) {
        if (mounted && state != null) {
          _activateLockout(state, showDialog: true);
          unawaited(_refreshLockoutFromServer(state.identifier));
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _username.dispose();
    _password.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreLockoutOnResume();
    }
  }

  Future<void> _restoreLockoutOnResume() async {
    final state = await Api.I.restoreLoginLockout();
    if (!mounted) return;
    final identifier = state?.identifier ?? _username.text.trim();
    if (state != null) {
      _activateLockout(state, showDialog: true);
    }
    if (identifier.isNotEmpty) {
      await _refreshLockoutFromServer(identifier);
    } else if (state == null) {
      _lockoutTimer?.cancel();
      setState(() {
        _lockoutExpiresAt = null;
        _lockoutRemainingSeconds = 0;
      });
    }
  }

  Future<void> _refreshLockoutFromServer(String identifier) async {
    try {
      final current = await Api.I.checkLoginLockout(identifier);
      if (!mounted) return;
      if (current == null) {
        _lockoutTimer?.cancel();
        _lockoutTimer = null;
        _lockoutExpiresAt = null;
        await Api.I.clearLoginLockout();
        if (_lockoutDialogOpen) _lockoutDialogKey.currentState?.dismiss();
        if (mounted) setState(() => _lockoutRemainingSeconds = 0);
        return;
      }
      await Api.I.saveLoginLockout(current);
      if (mounted) _activateLockout(current, showDialog: true);
    } on ApiException {
      // Keep the locally persisted expiry if the server cannot be reached.
    }
  }

  void _activateLockout(LoginLockoutState state, {required bool showDialog}) {
    final remaining = _secondsUntil(state.expiresAt);
    if (remaining <= 0) {
      unawaited(Api.I.clearLoginLockout());
      return;
    }
    _lockoutTimer?.cancel();
    if (state.identifier.isNotEmpty) _username.text = state.identifier;
    setState(() {
      _lockoutExpiresAt = state.expiresAt;
      _lockoutRemainingSeconds = remaining;
      _passwordResetRequired = false;
      _error = null;
      _errorStatusCode = null;
      _showRequestRecovery = false;
      _retryAction = null;
    });
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final expiresAt = _lockoutExpiresAt;
      if (!mounted || expiresAt == null) return;
      final seconds = _secondsUntil(expiresAt);
      if (seconds <= 0) {
        _lockoutTimer?.cancel();
        _lockoutTimer = null;
        setState(() => _lockoutRemainingSeconds = 1);
        unawaited(_confirmLockoutExpired());
        return;
      }
      setState(() => _lockoutRemainingSeconds = seconds);
    });
    if (showDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lockoutRemainingSeconds > 0) {
          _showLockoutDialog(state);
        }
      });
    }
  }

  Future<void> _confirmLockoutExpired() async {
    try {
      final current = await Api.I.checkLoginLockout(_username.text.trim());
      if (!mounted) return;
      if (current == null) {
        _lockoutExpiresAt = null;
        await Api.I.clearLoginLockout();
        if (mounted) setState(() => _lockoutRemainingSeconds = 0);
      } else {
        await Api.I.saveLoginLockout(current);
        if (mounted) _activateLockout(current, showDialog: true);
      }
    } on ApiException {
      if (mounted) {
        _lockoutTimer = Timer(
          const Duration(seconds: 5),
          _confirmLockoutExpired,
        );
      }
    }
  }

  int _secondsUntil(DateTime expiresAt) {
    final milliseconds = expiresAt
        .toUtc()
        .difference(DateTime.now().toUtc())
        .inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  Future<void> _showLockoutDialog(LoginLockoutState lockout) async {
    if (_lockoutDialogOpen || !mounted) return;
    _lockoutDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AccountLockoutDialog(
          key: _lockoutDialogKey,
          lockout: lockout,
          onForgotPassword: () => unawaited(_forgot(allowDuringLockout: true)),
        ),
      );
    } finally {
      _lockoutDialogOpen = false;
    }
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
      await _handleLoginError(e, identifier: _username.text.trim());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot({bool allowDuringLockout = false}) async {
    if (_lockoutRemainingSeconds > 0 && !allowDuringLockout) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _username.text.contains('@')
              ? _username.text.trim()
              : '',
        ),
      ),
    );
    if (!mounted) return;
    await _restoreLockoutOnResume();
    if (!mounted || _lockoutRemainingSeconds > 0) return;
    setState(() {
      // The backend remains authoritative if the user returned without
      // completing the reset; it will send the forced-reset response again.
      _passwordResetRequired = false;
      _error = null;
      _errorStatusCode = null;
      _showRequestRecovery = false;
      _retryAction = null;
    });
  }

  Future<void> _signInWithGoogle() async {
    if (_busy || _lockoutRemainingSeconds > 0 || _passwordResetRequired) return;
    var backendRequestStarted = false;
    var attemptedIdentifier = _username.text.trim();
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
      attemptedIdentifier = firebaseUser.email?.trim() ?? attemptedIdentifier;
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
      if (backendRequestStarted) {
        await _handleLoginError(
          e,
          identifier: attemptedIdentifier,
          googleAuthentication: true,
        );
      } else if (mounted) {
        setState(
          () => _error = 'Unable to sign in at the moment. Please try again.',
        );
      }
    } on GoogleSignInException catch (e, stackTrace) {
      debugPrint('Google sign-in failed (${e.code.name}): ${e.description}');
      debugPrintStack(stackTrace: stackTrace);
      final message = switch (e.code) {
        GoogleSignInExceptionCode.canceled => 'Google sign-in was canceled.',
        _ => 'Google sign-in could not be completed. Please try again.',
      };
      if (mounted) setState(() => _error = message);
    } on FirebaseAuthException catch (e, stackTrace) {
      debugPrint('Firebase Auth failed (${e.code}): ${e.message}');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(
          () => _error = switch (e.code) {
            'network-request-failed' =>
              'Unable to connect to the server. Please try again later.',
            'user-disabled' => 'Your account is currently inactive. Please contact the administrator.',
            _ => 'Unable to sign in at the moment. Please try again.',
          },
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

  Future<void> _signInWithFacebook() async {
    if (_busy || _lockoutRemainingSeconds > 0 || _passwordResetRequired) return;
    final testSignIn = widget.facebookSignInForTesting;
    if (testSignIn != null) {
      await testSignIn();
      return;
    }

    var backendRequestStarted = false;
    var attemptedIdentifier = _username.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _errorStatusCode = null;
      _showRequestRecovery = false;
      _retryAction = null;
    });
    try {
      final result =
          await (widget.facebookLoginResultForTesting?.call() ??
              FacebookAuth.instance.login(
                permissions: const ['public_profile', 'email'],
              ));
      if (result.status == LoginStatus.cancelled) return;
      if (result.status != LoginStatus.success || result.accessToken == null) {
        final hasInvalidScope =
            result.message?.toLowerCase().contains('invalid scopes') ?? false;
        debugPrint(
          'Facebook Login failed (${result.status.name}); '
          'invalidScope=$hasInvalidScope.',
        );
        if (mounted) {
          setState(
            () => _error = hasInvalidScope
                ? 'Facebook sign-in is not configured correctly. Please try another sign-in method or contact support.'
                : 'Facebook sign-in could not be completed. Please try again.',
          );
        }
        return;
      }

      final accessToken = result.accessToken!;
      final OAuthCredential credential = accessToken is LimitedToken
          ? OAuthProvider('facebook.com').credential(
              idToken: accessToken.tokenString,
              rawNonce: accessToken.nonce,
            )
          : FacebookAuthProvider.credential(accessToken.tokenString);
      final firebaseCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final firebaseUser = firebaseCredential.user;
      if (firebaseUser == null) {
        throw ApiException(
          'Firebase could not authenticate this Facebook account.',
        );
      }
      attemptedIdentifier = firebaseUser.email?.trim() ?? attemptedIdentifier;
      final firebaseIdToken = await firebaseUser.getIdToken(true);
      if (firebaseIdToken == null || firebaseIdToken.isEmpty) {
        throw ApiException('Firebase did not return a valid ID token.');
      }

      backendRequestStarted = true;
      await Api.I.loginWithFacebook(firebaseIdToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => homeForRole(Api.I.role)),
      );
    } on ApiException catch (e) {
      if (backendRequestStarted &&
          e.authAction == 'facebook_email_verification_required') {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FacebookEmailVerificationScreen(
                verification: FirebaseFacebookEmailVerification(),
                onVerified: _finishFacebookLogin,
              ),
            ),
          );
        }
      } else if (backendRequestStarted) {
        await _handleLoginError(
          e,
          identifier: attemptedIdentifier,
          googleAuthentication: true,
        );
      } else if (mounted) {
        setState(
          () => _error = 'Unable to sign in at the moment. Please try again.',
        );
      }
    } on FirebaseAuthException catch (e, stackTrace) {
      debugPrint('Firebase Auth failed (${e.code}): ${e.message}');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(
          () => _error = e.code == 'network-request-failed'
              ? 'Unable to connect to the server. Please try again later.'
              : 'Unable to sign in at the moment. Please try again.',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Facebook sign-in failed (${e.runtimeType}).');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(
          () => _error =
              'Facebook sign-in could not be completed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishFacebookLogin(String firebaseIdToken) async {
    await Api.I.loginWithFacebook(firebaseIdToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => homeForRole(Api.I.role)),
      (_) => false,
    );
  }

  Future<void> _handleLoginError(
    ApiException error, {
    required String identifier,
    bool googleAuthentication = false,
  }) async {
    if (error.securityStatus == 'locked' && error.statusCode == 429) {
      final expiry =
          error.lockedUntil ??
          (error.retryAfterSeconds != null
              ? DateTime.now().toUtc().add(
                  Duration(seconds: error.retryAfterSeconds!),
                )
              : null);
      if (expiry != null && expiry.isAfter(DateTime.now().toUtc())) {
        final state = LoginLockoutState(
          identifier: identifier,
          expiresAt: expiry.toUtc(),
          durationSeconds:
              error.lockoutDurationSeconds ?? error.retryAfterSeconds ?? 0,
          cycle: error.lockoutCycle ?? 0,
        );
        await Api.I.saveLoginLockout(state);
        if (mounted) _activateLockout(state, showDialog: true);
        return;
      }
    }

    final message = switch (error.statusCode) {
      401 when googleAuthentication =>
        'Unable to sign in at the moment. Please try again.',
      401 => 'Incorrect username or password. Please check your credentials and try again.',
      403 =>
        'Your account is currently inactive. Please contact the administrator.',
      429 when error.passwordResetRequired =>
        'Your account needs a password reset before you can sign in.',
      429 when error.securityStatus == 'locked' => 'Your account is temporarily locked. Please try again when the countdown ends.',
      429 => 'Too many sign-in attempts. Please wait a moment and try again.',
      500 => 'Something went wrong. Please try again later.',
      null => 'Unable to connect to the server. Please try again later.',
      _ => 'Unable to sign in at the moment. Please try again.',
    };
    if (!mounted) return;
    setState(() {
      if (error.passwordResetRequired && identifier.isNotEmpty) {
        _username.text = identifier;
      }
      _error = message;
      _errorStatusCode = null;
      _showRequestRecovery = false;
      _retryAction = null;
      _passwordResetRequired = error.passwordResetRequired;
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
    final locked = _lockoutRemainingSeconds > 0;
    return PopScope(
      canPop: !locked,
      child: Scaffold(
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
                        enabled: !locked,
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
                        enabled: !locked,
                        obscureText: _hide,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _busy ? null : _submit(),
                        decoration: _dec(
                          'Password',
                          Icons.lock_outline,
                          suffix: locked
                              ? null
                              : IconButton(
                                  icon: Icon(
                                    _hide
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                  onPressed: () =>
                                      setState(() => _hide = !_hide),
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
                                onChanged: locked
                                    ? null
                                    : (v) =>
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
                              onPressed: locked ? null : _forgot,
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
                          onPressed: _busy || locked ? null : _forgot,
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary,
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
                      const SizedBox(height: 12),
                      _socialButton(
                        label: 'Continue with Facebook',
                        icon: const Icon(
                          Icons.facebook,
                          color: Color(0xFF1877F2),
                          size: 24,
                        ),
                        onTap: _busy || locked || _passwordResetRequired
                            ? () {}
                            : _signInWithFacebook,
                      ),

                      // ---------- OPEN REGISTRATION ----------
                      const SizedBox(height: 22),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
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

class _AccountLockoutDialog extends StatefulWidget {
  const _AccountLockoutDialog({
    super.key,
    required this.lockout,
    required this.onForgotPassword,
  });

  final LoginLockoutState lockout;
  final VoidCallback onForgotPassword;

  @override
  State<_AccountLockoutDialog> createState() => _AccountLockoutDialogState();
}

class _AccountLockoutDialogState extends State<_AccountLockoutDialog> {
  Timer? _timer;
  int _remaining = 0;
  bool _canClose = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateRemaining(),
    );
  }

  void _updateRemaining() {
    final milliseconds = widget.lockout.expiresAt
        .toUtc()
        .difference(DateTime.now().toUtc())
        .inMilliseconds;
    final seconds = milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
    if (!mounted) return;
    if (seconds == 0) {
      _timer?.cancel();
      _closeDialog();
      return;
    }
    setState(() => _remaining = seconds);
  }

  void _closeDialog() {
    if (!mounted || _closing) return;
    _closing = true;
    setState(() => _canClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void dismiss() => _closeDialog();

  void _openForgotPassword() {
    if (!mounted || _closing) return;
    _closing = true;
    setState(() => _canClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onForgotPassword();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = (_remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remaining % 60).toString().padLeft(2, '0');
    final totalSeconds = widget.lockout.durationSeconds > 0
        ? widget.lockout.durationSeconds
        : _remaining;
    final progress = (totalSeconds > 0 ? _remaining / totalSeconds : 0.0).clamp(
      0.0,
      1.0,
    );
    return PopScope(
      canPop: _canClose,
      child: AlertDialog(
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.security_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 30,
          ),
        ),
        title: const Text(
          'Account Temporarily Locked',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Too many unsuccessful login attempts have been detected.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 132,
              height: 132,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: progress),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .errorContainer,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  Text(
                    '$minutes:$seconds',
                    key: const ValueKey('lockout-countdown'),
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Please wait until the countdown finishes before trying again.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: _openForgotPassword,
            child: const Text('Forgot Password?'),
          ),
          FilledButton(onPressed: _closeDialog, child: const Text('OK')),
        ],
      ),
    );
  }
}
