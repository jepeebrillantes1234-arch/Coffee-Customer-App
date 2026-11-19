import 'package:flutter/material.dart';

import 'api.dart';

/// Shared KJM loading treatment for customer and rider screens.
/// The animation is local to this widget and never starts a network request.
class KjmLoadingView extends StatelessWidget {
  const KjmLoadingView({
    super.key,
    this.message,
    this.compact = false,
    this.connectionRecovery = false,
  });

  /// Retained for source compatibility; customer-facing copy is standardized.
  final String? message;
  final bool compact;
  final bool connectionRecovery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!connectionRecovery) {
      return compact
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Center(child: CircularProgressIndicator());
    }

    return Semantics(
      liveRegion: true,
      label: message == null ? 'Loading...' : 'Loading... $message',
      child: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AnimatedKjmLogo(size: 34),
                const SizedBox(width: 8),
                Text(
                  'Loading...',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AnimatedKjmLogo(size: 58),
                  const SizedBox(height: 10),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Shows the logo recovery screen only while Api is retrying a safe read after
/// a transient connection or server failure. Ordinary screen loads use local
/// indicators and do not activate this overlay.
class KjmConnectionRecoveryOverlay extends StatelessWidget {
  const KjmConnectionRecoveryOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: Api.I.connectionRecoveryActive,
    builder: (context, recovering, _) {
      if (!recovering) return child;
      return Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface.withAlpha(245),
              child: const KjmLoadingView(connectionRecovery: true),
            ),
          ),
        ],
      );
    },
  );
}

class _AnimatedKjmLogo extends StatefulWidget {
  const _AnimatedKjmLogo({required this.size});

  final double size;

  @override
  State<_AnimatedKjmLogo> createState() => _AnimatedKjmLogoState();
}

class _AnimatedKjmLogoState extends State<_AnimatedKjmLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: Image.asset(
      'assets/images/logo1.png',
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
    ),
  );
}

/// Compact request failure feedback. Retry is available only when the caller
/// supplies a safe, user-triggered request callback.
class KjmErrorNotice extends StatelessWidget {
  const KjmErrorNotice({
    super.key,
    required this.message,
    required this.onRetry,
    this.onBack,
    this.statusCode,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onBack;
  final int? statusCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Unable to Load Page',
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Something went wrong while loading this page. Would you like to try again?',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            if (statusCode != null) ...[
              const SizedBox(height: 6),
              Text(
                'HTTP $statusCode',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
                OutlinedButton.icon(
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-page error state. A failed request never leaves an animated spinner
/// running. Callers should pass a retry callback only for safe read requests.
class KjmErrorState extends StatelessWidget {
  const KjmErrorState({
    super.key,
    this.exception,
    this.message,
    this.statusCode,
    this.title,
    this.instruction,
    required this.onRetry,
    this.onBack,
  });

  final ApiException? exception;
  final String? message;
  final int? statusCode;
  final String? title;
  final String? instruction;
  final VoidCallback onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = exception?.statusCode ?? statusCode;
    final effectiveCode = code ?? statusCode;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 34, color: scheme.error),
                  const SizedBox(height: 10),
                  Text(
                    'Unable to Load Page',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Something went wrong while loading this page. Would you like to try again?',
                    textAlign: TextAlign.center,
                  ),
                  if (effectiveCode != null) ...[
                    const SizedBox(height: 12),
                    Text('HTTP $effectiveCode', textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            onBack ?? () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Go Back'),
                      ),
                    ],
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

/// Form errors are not page-load errors: preserve their original messages and
/// field validation flow without showing recovery controls that could resubmit.
class KjmInlineError extends StatelessWidget {
  const KjmInlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Text(message, style: TextStyle(color: scheme.error)),
    );
  }
}
