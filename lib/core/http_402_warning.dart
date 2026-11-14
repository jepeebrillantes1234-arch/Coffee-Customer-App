import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

typedef Http402RetryRequest = Future<Map<String, dynamic>> Function();

class Http402Warning {
  static bool _dialogOpen = false;

  static Future<Map<String, dynamic>?> show({
    required GlobalKey<NavigatorState> navigatorKey,
    required Uri? productionWebsite,
    required Http402RetryRequest? retryRequest,
    String? serverMessage,
    required VoidCallback onContactAdministrator,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null || _dialogOpen) return null;
    _dialogOpen = true;
    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) {
          var retrying = false;
          String? retryError;

          return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Service requires attention'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'The server rejected this request with HTTP 402 (Payment Required). This can happen when a service or account needs attention. A connection retry may help with a temporary gateway problem, but it cannot resolve billing or account restrictions.',
                      ),
                      if (serverMessage != null) ...[
                        const SizedBox(height: 10),
                        Text('Server message: $serverMessage'),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Try these steps:',
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '1. Check your internet connection.\n'
                        '2. Wait briefly, then retry this request if the option is available.\n'
                        '3. If the error continues, contact the administrator.\n'
                        '4. Do not repeat a payment or place the same order again from this warning.',
                      ),
                      if (retrying) ...[
                        const SizedBox(height: 14),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('Retrying the failed request...'),
                      ],
                      if (retryError != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Retry failed: $retryError',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: retrying
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                          onContactAdministrator();
                        },
                  child: const Text('Contact Administrator'),
                ),
                if (retryRequest != null)
                  FilledButton.tonal(
                    onPressed: retrying
                        ? null
                        : () async {
                            setState(() {
                              retrying = true;
                              retryError = null;
                            });
                            try {
                              final response = await retryRequest();
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop(response);
                              }
                            } catch (error) {
                              if (dialogContext.mounted) {
                                setState(() {
                                  retrying = false;
                                  retryError = error.toString().replaceFirst(
                                    'ApiException: ',
                                    '',
                                  );
                                });
                              }
                            }
                          },
                    child: Text(retrying ? 'Retrying...' : 'Retry Connection'),
                  ),
                if (productionWebsite != null)
                  TextButton(
                    onPressed: retrying
                        ? null
                        : () async {
                            Navigator.of(dialogContext).pop();
                            await launchUrl(
                              productionWebsite,
                              mode: LaunchMode.externalApplication,
                            );
                          },
                    child: const Text('Open Official Website'),
                  ),
                TextButton(
                  onPressed: retrying
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _dialogOpen = false;
    }
  }
}
