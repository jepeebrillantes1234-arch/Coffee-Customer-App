import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';

/// Shared loading treatment for customer and rider screens. The animation is
/// local to the widget and never starts or repeats a network request.
class KjmLoadingView extends StatelessWidget {
  const KjmLoadingView({
    super.key,
    this.message = 'Loading…',
    this.compact = false,
  });

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: compact ? 20 : 42,
      height: compact ? 20 : 42,
      child: const CircularProgressIndicator(strokeWidth: 3),
    );

    if (compact) {
      return Semantics(
        liveRegion: true,
        label: message,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [indicator, const SizedBox(width: 10), Text(message)],
        ),
      );
    }

    return Center(
      child: Semantics(
        liveRegion: true,
        label: message,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            indicator,
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Responsive, reusable error state. Supplying [onRetry] is an explicit
/// user-triggered action; callers should only provide it for safe requests.
class KjmErrorState extends StatefulWidget {
  const KjmErrorState({
    super.key,
    this.exception,
    this.message,
    this.statusCode,
    this.title,
    this.instruction,
    this.onRetry,
    this.onBack,
  });

  final ApiException? exception;
  final String? message;
  final int? statusCode;
  final String? title;
  final String? instruction;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  @override
  State<KjmErrorState> createState() => _KjmErrorStateState();
}

/// Compact animated error feedback for forms and screens that can preserve
/// their current contents while showing a request failure.
class KjmErrorNotice extends StatefulWidget {
  const KjmErrorNotice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  State<KjmErrorNotice> createState() => _KjmErrorNoticeState();
}

class _KjmErrorNoticeState extends State<KjmErrorNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = RegExp(r'^HTTP\s+(\d{3})\s*:\s*').firstMatch(widget.message);
    final code = match?.group(1);
    final message = widget.message.replaceFirst(
      RegExp(r'^HTTP\s+\d{3}\s*:\s*'),
      '',
    );
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RotationTransition(
              turns: _rotation,
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: scheme.error,
                  backgroundColor: scheme.onErrorContainer.withValues(
                    alpha: .12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code == null ? 'Request failed' : 'HTTP $code',
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ],
              ),
            ),
            if (widget.onRetry != null)
              TextButton(onPressed: widget.onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _KjmErrorStateState extends State<KjmErrorState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  int? get _code {
    if (widget.exception?.statusCode != null) {
      return widget.exception!.statusCode;
    }
    if (widget.statusCode != null) return widget.statusCode;
    final match = RegExp(r'^HTTP\s+(\d{3})\s*:')
        .firstMatch(widget.message ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  String get _message {
    final value =
        widget.exception?.message ??
        widget.message ??
        'The request could not be completed.';
    return value.replaceFirst(RegExp(r'^HTTP\s+\d{3}\s*:\s*'), '');
  }

  String get _title {
    if (widget.title != null) return widget.title!;
    if (widget.exception != null) return widget.exception!.title;
    return switch (_code) {
      400 => 'Request could not be understood',
      401 => 'Sign in again',
      403 => 'Access denied',
      404 => 'Not found',
      405 => 'Action unavailable',
      408 || 504 => 'Request timed out',
      409 => 'Information changed',
      413 => 'File upload failed',
      419 => 'Session expired',
      422 => 'Check your information',
      429 => 'Please wait before trying again',
      500 => 'Something went wrong',
      502 => 'Service interruption',
      503 => 'Service unavailable',
      _ => 'Something went wrong',
    };
  }

  String get _instruction =>
      widget.instruction ??
      widget.exception?.instruction ??
      'Check your connection and try again. For an order or payment, check its status before submitting again.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canGoBack = widget.onBack != null || Navigator.of(context).canPop();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo1.png',
                    width: 54,
                    height: 54,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.coffee, size: 42, color: espresso),
                  ),
                  const SizedBox(height: 14),
                  RotationTransition(
                    turns: _rotation,
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: const Color(0xFFC49A6C),
                        backgroundColor: scheme.outlineVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _code?.toString() ?? '!',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: const Color(0xFFC49A6C),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _instruction,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (widget.onRetry != null)
                        FilledButton.icon(
                          onPressed: widget.onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      if (canGoBack)
                        OutlinedButton.icon(
                          onPressed:
                              widget.onBack ??
                              () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Go back'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'KJM Coffee Shop',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: espresso,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
