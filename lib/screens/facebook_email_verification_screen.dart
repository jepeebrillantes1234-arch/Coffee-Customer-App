import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';

abstract interface class FacebookEmailVerification {
  String? get facebookEmail;
  Future<void> sendVerificationToFacebookEmail();
  Future<void> verifyBeforeUpdatingEmail(String newEmail);
  Future<String?> reloadAndGetVerifiedIdToken();
}

class FirebaseFacebookEmailVerification implements FacebookEmailVerification {
  FirebaseFacebookEmailVerification({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance,
      _uid = (auth ?? FirebaseAuth.instance).currentUser?.uid;

  final FirebaseAuth _auth;
  final String? _uid;

  User _currentFacebookUser() {
    final user = _auth.currentUser;
    if (user == null || user.uid != _uid || _uid == null) {
      throw StateError('The Facebook sign-in session is no longer available.');
    }
    if (!user.providerData.any((info) => info.providerId == 'facebook.com')) {
      throw StateError('The current Firebase account is not Facebook-linked.');
    }
    return user;
  }

  @override
  String? get facebookEmail => _auth.currentUser?.email;

  @override
  Future<void> sendVerificationToFacebookEmail() async {
    final email = _currentFacebookUser().email;
    if (email == null || email.trim().isEmpty) {
      throw StateError(
        'This Facebook account does not provide an email address.',
      );
    }
    await _currentFacebookUser().sendEmailVerification();
  }

  @override
  Future<void> verifyBeforeUpdatingEmail(String newEmail) async {
    final email = newEmail.trim();
    if (email.isEmpty) throw ArgumentError.value(newEmail, 'newEmail');
    await _currentFacebookUser().verifyBeforeUpdateEmail(email);
  }

  @override
  Future<String?> reloadAndGetVerifiedIdToken() async {
    await _currentFacebookUser().reload();
    final refreshedUser = _currentFacebookUser();
    if (!refreshedUser.emailVerified) return null;
    return refreshedUser.getIdToken(true);
  }
}

class FacebookEmailVerificationScreen extends StatefulWidget {
  const FacebookEmailVerificationScreen({
    super.key,
    required this.verification,
    required this.onVerified,
  });

  final FacebookEmailVerification verification;
  final Future<void> Function(String firebaseIdToken) onVerified;

  @override
  State<FacebookEmailVerificationScreen> createState() =>
      _FacebookEmailVerificationScreenState();
}

class _FacebookEmailVerificationScreenState
    extends State<FacebookEmailVerificationScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _message;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkVerification();
    }
  }

  Future<void> _sendFacebookEmail() async {
    await _run(() async {
      await widget.verification.sendVerificationToFacebookEmail();
      return 'We sent a verification link. Open it, then return to this app.';
    });
  }

  Future<void> _chooseAnotherEmail() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => const _AlternateEmailDialog(),
    );
    if (email != null && mounted) {
      await _run(() async {
        await widget.verification.verifyBeforeUpdatingEmail(email);
        return 'We sent a verification link. Verify the new address, then return to this app.';
      });
    }
  }

  Future<void> _checkVerification() => _run(() async {
    if (_checking) return null;
    _checking = true;
    try {
      final token = await widget.verification.reloadAndGetVerifiedIdToken();
      if (token == null || token.isEmpty) {
        return 'Email verification is not complete yet. Open the link and try again.';
      }
      await widget.onVerified(token);
      return null;
    } finally {
      _checking = false;
    }
  });

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    String? message;
    try {
      message = await action();
    } on FirebaseAuthException catch (error) {
      message = switch (error.code) {
        'email-already-in-use' || 'credential-already-in-use' => 'That email cannot be used for this account. Try another address or contact support.',
        'network-request-failed' =>
          'Unable to connect to the verification service. Please try again.',
        _ => 'We could not complete email verification. Please try again or contact support.',
      };
    } on ApiException catch (error) {
      message = error.statusCode == 409
          ? 'This email is already associated with another account. Use that account to sign in or contact support.'
          : 'We could not complete sign-in after verification. Please try again.';
    } on StateError catch (error) {
      message = error.message.toString();
    } catch (_) {
      message = 'We could not complete email verification. Please try again.';
    }
    if (!mounted) return;
    setState(() {
      _message = message;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasFacebookEmail =
        (widget.verification.facebookEmail?.trim().isNotEmpty ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Verify an email to continue',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Laravel could not verify this Facebook email. Verify it, or use another email you can access. Your account will not be created until verification succeeds.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy || !hasFacebookEmail
                        ? null
                        : _sendFacebookEmail,
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Verify Facebook email'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _chooseAnotherEmail,
                    icon: const Icon(Icons.alternate_email),
                    label: const Text('Use another email address'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy ? null : _checkVerification,
                    child: const Text("I've verified my email"),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlternateEmailDialog extends StatefulWidget {
  const _AlternateEmailDialog();

  @override
  State<_AlternateEmailDialog> createState() => _AlternateEmailDialogState();
}

class _AlternateEmailDialogState extends State<_AlternateEmailDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Use another email'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email address'),
        validator: (value) {
          final email = value?.trim() ?? '';
          return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
              ? null
              : 'Enter a valid email address.';
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Send verification')),
    ],
  );
}
