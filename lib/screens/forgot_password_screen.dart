import 'package:flutter/material.dart';

import '../core/api.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await Api.I.forgotPassword(_email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We could not send the reset link. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot password'),
        leading: IconButton(
          tooltip: 'Back to login',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                    side: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: .55),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(
                      constraints.maxWidth < 380 ? 22 : 30,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _sent
                          ? _successContent(colors)
                          : _formContent(colors),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formContent(ColorScheme colors) => Form(
    key: _formKey,
    child: Column(
      key: const ValueKey('forgot-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _iconBadge(Icons.lock_reset_rounded, colors),
        const SizedBox(height: 22),
        const Text(
          'A fresh start for your account',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          'Enter the email address linked to your account. We’ll send instructions to reset your password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _email,
          enabled: !_sending,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          onFieldSubmitted: (_) => _sending ? null : _sendResetLink(),
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'you@example.com',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            if (email.isEmpty) return 'Enter your email address.';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
              return 'Enter a valid email address.';
            }
            return null;
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _messageBox(_error!, colors, isError: true),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _sending ? null : _sendResetLink,
          icon: _sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mark_email_read_outlined),
          label: Text(_sending ? 'Sending…' : 'Send reset link'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Back to Login'),
        ),
      ],
    ),
  );

  Widget _successContent(ColorScheme colors) => Column(
    key: const ValueKey('forgot-success'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _iconBadge(Icons.mark_email_read_rounded, colors, success: true),
      const SizedBox(height: 22),
      const Text(
        'Check your inbox',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      Text(
        'If ${_email.text.trim()} is registered, password reset instructions have been sent.',
        textAlign: TextAlign.center,
        style: TextStyle(color: colors.onSurfaceVariant, height: 1.45),
      ),
      const SizedBox(height: 24),
      _messageBox(
        'For your security, we show the same confirmation whether or not the address has an account.',
        colors,
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.login_rounded),
        label: const Text('Return to Login'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      ),
      TextButton(
        onPressed: _sending ? null : () => setState(() => _sent = false),
        child: const Text('Use a different email'),
      ),
    ],
  );

  Widget _iconBadge(
    IconData icon,
    ColorScheme colors, {
    bool success = false,
  }) => Center(
    child: Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: success
            ? const Color(0xFFE8F2E9)
            : colors.secondaryContainer.withValues(alpha: .75),
      ),
      child: Icon(
        icon,
        size: 36,
        color: success ? const Color(0xFF3C7850) : colors.primary,
      ),
    ),
  );

  Widget _messageBox(String text, ColorScheme colors, {bool isError = false}) =>
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isError
              ? colors.errorContainer.withValues(alpha: .65)
              : colors.secondaryContainer.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              size: 19,
              color: isError ? colors.error : colors.primary,
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
          ],
        ),
      );
}
