import 'package:flutter/material.dart';

import 'config.dart';

String fixUrl(String? u) {
  if (u == null || u.isEmpty) return '';
  final raw = u.trim();
  final base = Uri.tryParse(AppConfig.apiBase);
  var uri = Uri.tryParse(raw);
  if (base == null || uri == null) return raw;
  // A phone cannot reach the development computer through its own localhost.
  // Reuse the API host while preserving Laravel's /storage/... path.
  if (uri.host == 'localhost' ||
      uri.host == '127.0.0.1' ||
      uri.host == '0.0.0.0') {
    uri = Uri(
      scheme: base.scheme,
      userInfo: uri.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : 0,
      pathSegments: uri.pathSegments,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
  } else if (uri.host != base.host &&
      uri.host.endsWith('.ngrok-free.dev') &&
      base.host.endsWith('.ngrok-free.dev')) {
    // Laravel may build storage URLs using an older APP_URL/ngrok hostname.
    // Keep the uploaded file path, but fetch it from the currently configured
    // API tunnel so banners and other uploaded images remain reachable.
    uri = Uri(
      scheme: base.scheme,
      userInfo: uri.userInfo,
      host: base.host,
      port: base.hasPort ? base.port : null,
      pathSegments: uri.pathSegments,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
  } else if (uri.scheme == 'http' && uri.host.contains('ngrok')) {
    uri = uri.replace(scheme: 'https');
  }
  return uri.toString();
}

class NetImage extends StatelessWidget {
  final String? url;
  final double? height;
  final double? width;
  final BoxFit fit;
  const NetImage(
    this.url, {
    super.key,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final u = fixUrl(url);
    final placeholder = Container(
      height: height,
      width: width,
      color: Colors.brown.shade100,
      alignment: Alignment.center,
      child: const Text('☕', style: TextStyle(fontSize: 32)),
    );
    if (u.isEmpty) return placeholder;
    return Image.network(
      u,
      height: height,
      width: width,
      fit: fit,
      headers: const {'ngrok-skip-browser-warning': 'true'},
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Stack(
              alignment: Alignment.center,
              children: [
                placeholder,
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress.expectedTotalBytes == null
                        ? null
                        : progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!,
                  ),
                ),
              ],
            ),
      errorBuilder: (_, error, _) {
        debugPrint('Image load failed: $u | $error');
        return placeholder;
      },
    );
  }
}
