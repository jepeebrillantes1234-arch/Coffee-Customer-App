import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';

/// Shared KJM loading treatment for customer and rider screens.
/// The animation is local to this widget and never starts a network request.
class KjmLoadingView extends StatelessWidget {
  const KjmLoadingView({super.key, this.message, this.compact = false});

  /// Retained for source compatibility; customer-facing copy is standardized.
  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final indicator = SizedBox(
      width: compact ? 24 : 42,
      height: compact ? 24 : 42,
      child: CircularProgressIndicator(
        strokeWidth: compact ? 2.5 : 3,
        color: const Color(0xFFC49A6C),
        backgroundColor: scheme.outlineVariant,
      ),
    );

    final copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        const Text('Loading...', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          'Please wait while we load your page.',
          textAlign: compact ? TextAlign.start : TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );

    return Semantics(
      liveRegion: true,
      label: 'Loading... Please wait while we load your page.',
      child: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                indicator,
                const SizedBox(width: 10),
                Flexible(child: copy),
              ],
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [indicator, const SizedBox(height: 14), copy],
              ),
            ),
    );
  }
}

/// Compact request failure feedback. Retry is available only when the caller
/// supplies a safe, user-triggered request callback.
class KjmErrorNotice extends StatelessWidget {
  const KjmErrorNotice({
    super.key,
    required this.message,
    this.onRetry,
    this.onBack,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const canGoBack = true;
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
            if (message.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(message, style: TextStyle(color: scheme.onErrorContainer)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                if (canGoBack)
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = exception?.statusCode ?? statusCode;
    final detail = message ?? exception?.message;
    final recoveryHint = instruction ?? exception?.instruction;
    final statusLabel = title ?? exception?.title;
    const canGoBack = true;
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
                  const SizedBox(height: 16),
                  Icon(Icons.error_outline, size: 44, color: scheme.error),
                  const SizedBox(height: 14),
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
                  if (code != null ||
                      statusLabel != null ||
                      detail != null ||
                      recoveryHint != null) ...[
                    const SizedBox(height: 12),
                    if (code != null || statusLabel != null)
                      Text(
                        [
                          if (code != null) 'HTTP $code',
                          ?statusLabel,
                        ].join(' / '),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    if (detail != null && detail.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(detail, textAlign: TextAlign.center),
                    ],
                    if (recoveryHint != null &&
                        recoveryHint.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        recoveryHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                  const SizedBox(height: 22),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (onRetry != null)
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      if (canGoBack)
                        OutlinedButton.icon(
                          onPressed:
                              onBack ?? () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Go Back'),
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
