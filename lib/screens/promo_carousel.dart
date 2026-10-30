import 'package:flutter/material.dart';

import '../core/widgets.dart';
import '../state/promo_state.dart';

/// Banner ng promo: BUONG LARAWAN na may text sa ibabaw.
/// Ang text (title, headline, description) ay galing sa Admin > Promos.
/// - Kapag blangko ang lahat ng text, larawan lang ang ipapakita.
/// - Gamitin sa Home carousel (walang aspectRatio, pupunuin ang espasyo)
///   at sa Promos page (aspectRatio: 2).
class PromoBannerCard extends StatelessWidget {
  final Map<String, dynamic> promo;
  final VoidCallback? onTap;
  final double? aspectRatio;
  final double radius;

  const PromoBannerCard({
    super.key,
    required this.promo,
    this.onTap,
    this.aspectRatio,
    this.radius = 20,
  });

  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 8)];

  @override
  Widget build(BuildContext context) {
    final card = ListenableBuilder(
      listenable: SelectedPromo.I,
      builder: (_, _) => _buildCard(),
    );
    if (aspectRatio == null) return card;
    return AspectRatio(aspectRatio: aspectRatio!, child: card);
  }

  Widget _buildCard() {
    final img = (promo['image_url'] ?? '').toString();
    final title = (promo['title'] ?? '').toString().trim();
    final headline = (promo['headline'] ?? '').toString().trim();
    final desc = (promo['description'] ?? '').toString().trim();
    final code = (promo['code'] ?? '').toString();
    final used = promo['used'] == true;
    final per = (promo['per_user_limit'] as num?)?.toInt() ?? 1;
    final selected = code.isNotEmpty && SelectedPromo.I.code == code;
    final hasText = title.isNotEmpty || headline.isNotEmpty || desc.isNotEmpty;

    final pillText = used ? 'Used' : (selected ? 'Selected' : 'Use promo');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 2),
        child: Material(
          color: const Color(0xFF111111),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ---------- BUONG LARAWAN ----------
                if (img.isNotEmpty)
                  NetImage(img, fit: BoxFit.cover)
                else
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF383838), Color(0xFF111111)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.local_cafe, size: 64, color: Color(0x44FFFFFF)),
                    ),
                  ),

                // ---------- DILIM PARA MABASA ANG TEXT ----------
                if (hasText)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.72),
                          Colors.black.withValues(alpha: 0.30),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),

                // ---------- TEXT SA IBABAW ----------
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasText)
                        FractionallySizedBox(
                          widthFactor: 0.78,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (title.isNotEmpty)
                                Text(
                                  title.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.4,
                                    shadows: _shadow,
                                  ),
                                ),
                              if (headline.isNotEmpty)
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    headline,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      fontStyle: FontStyle.italic,
                                      height: 1.1,
                                      shadows: _shadow,
                                    ),
                                  ),
                                ),
                              if (desc.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    desc,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      height: 1.3,
                                      shadows: _shadow,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (hasText && code.isNotEmpty)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white54),
                                ),
                                child: Text(
                                  '$code · ${per == 1 ? '1 gamit lang' : '$per gamit'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF3C8D5A) : Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  pillText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: selected ? Colors.white : const Color(0xFF111111),
                                  ),
                                ),
                                Icon(
                                  selected ? Icons.check : Icons.chevron_right,
                                  size: 16,
                                  color: selected ? Colors.white : const Color(0xFF111111),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ---------- NAGAMIT NA ----------
                if (used)
                  Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    alignment: Alignment.center,
                    child: const Text(
                      'NAGAMIT MO NA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
