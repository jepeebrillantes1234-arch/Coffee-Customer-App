import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/widgets.dart';

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Map<String, dynamic>? _membership;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _rewards = [];
  List<Map<String, dynamic>> _redemptions = [];
  int _monthlyPointsValue = 0;
  bool _loading = true;
  bool _busy = false;
  bool _verifying = false;
  String? _error;
  late final AnimationController _cardFlipController;

  bool get _active => _membership?['active'] == true;
  int get _points => (_membership?['points_balance'] as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _cardFlipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cardFlipController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_active) _verifyPayment();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        Api.I.loyaltySummary(),
        Api.I.rewards(),
        Api.I.rewardRedemptions(),
      ]);
      if (!mounted) return;
      final summary = values[0] as Map<String, dynamic>;
      setState(() {
        _membership = summary['membership'] is Map
            ? Map<String, dynamic>.from(summary['membership'] as Map)
            : null;
        _transactions = (summary['transactions'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _monthlyPointsValue = (summary['monthly_points'] as num?)?.toInt() ?? 0;
        _rewards = values[1] as List<Map<String, dynamic>>;
        _redemptions = values[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load membership details: $error';
        _loading = false;
      });
    }
  }

  Future<void> _startPayment() async {
    setState(() => _busy = true);
    try {
      final checkout = await Api.I.startMembershipCheckout();
      final url = fixUrl(checkout['checkout_url']?.toString());
      if (url.isEmpty) {
        throw ApiException('The payment page is not available. Please retry.');
      }
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw ApiException('Could not open the payment page.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complete the â‚±100 payment, then return here.'),
          ),
        );
      }
      await _refreshQuietly();
    } on ApiException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('Could not start membership payment: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyPayment() async {
    if (_verifying || _active) return;
    _verifying = true;
    try {
      final summary = await Api.I.verifyMembershipPayment();
      if (!mounted) return;
      setState(() {
        _membership = summary['membership'] is Map
            ? Map<String, dynamic>.from(summary['membership'] as Map)
            : null;
        _transactions = (summary['transactions'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _monthlyPointsValue = (summary['monthly_points'] as num?)?.toInt() ?? 0;
      });
      if (_active) _message('Membership activated successfully.');
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      _verifying = false;
    }
  }

  Future<void> _refreshQuietly() async {
    try {
      final summary = await Api.I.loyaltySummary();
      if (!mounted) return;
      setState(() {
        _membership = summary['membership'] is Map
            ? Map<String, dynamic>.from(summary['membership'] as Map)
            : null;
        _transactions = (summary['transactions'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _redeem(Map<String, dynamic> reward) async {
    final name = reward['name']?.toString() ?? 'this reward';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem reward?'),
        content: Text('Use ${reward['points_cost']} points for $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final key = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      final result = await Api.I.redeemReward(
        (reward['id'] as num).toInt(),
        key,
      );
      final redemption = Map<String, dynamic>.from(result);
      await _load();
      if (mounted) await _showRedemption(redemption);
    } on ApiException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('Could not redeem this reward: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRedemption(Map<String, dynamic> redemption) async {
    final code = redemption['code']?.toString() ?? '';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reward redeemed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (code.isNotEmpty)
              QrImageView(
                data: code,
                version: QrVersions.auto,
                size: 190,
                backgroundColor: Colors.white,
              ),
            const SizedBox(height: 10),
            SelectableText(
              code,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text('Show this code to staff when claiming your reward.'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Membership & Rewards')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (_error != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(_error!),
                        trailing: IconButton(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ),
                  _membershipCard(colors),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          'Current points',
                          '$_points',
                          Icons.stars_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricCard(
                          'Earned this month',
                          '$_monthlyPointsValue',
                          Icons.calendar_month_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _sectionTitle('Available rewards'),
                  if (_rewards.isEmpty)
                    const _EmptyNotice('No rewards are available right now.'),
                  for (final reward in _rewards) _rewardCard(reward),
                  const SizedBox(height: 22),
                  _sectionTitle('Redemption history'),
                  if (_redemptions.isEmpty)
                    const _EmptyNotice('Your redeemed rewards will appear here.'),
                  for (final redemption in _redemptions)
                    _redemptionRow(redemption),
                  const SizedBox(height: 22),
                  _sectionTitle('Points history'),
                  if (_transactions.isEmpty)
                    const _EmptyNotice('Points earned and redeemed will appear here.'),
                  for (final transaction in _transactions)
                    _transactionRow(transaction),
                ],
              ),
            ),
      floatingActionButton: _busy
          ? const FloatingActionButton(onPressed: null, child: CircularProgressIndicator())
          : null,
    );
  }

  Widget _membershipCard(ColorScheme colors) {
    final memberId = _membership?['member_id']?.toString() ?? 'Issued after payment';
    final latestPayment = _membership?['latest_payment'];
    final paymentPending = latestPayment is Map && latestPayment['status'] == 'pending';
    final memberSince = _formatMemberSince(
      _active
          ? (_membership?['member_since'] ??
                _membership?['activated_at'] ??
                _membership?['created_at'])
          : null,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _cardFlipController,
              builder: (context, _) {
                final angle = _cardFlipController.value * pi;
                final showBack = angle >= pi / 2;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final height = width / (1024 / 450);
                    return SizedBox(
                      width: width,
                      height: height,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(angle),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(showBack ? pi : 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: showBack
                                ? _membershipCardBack()
                                : _membershipCardFront(
                                    width: width,
                                    height: height,
                                    memberId: memberId,
                                    memberSince: memberSince,
                                  ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () {
                if (_cardFlipController.value < 0.5) {
                  _cardFlipController.forward();
                } else {
                  _cardFlipController.reverse();
                }
              },
              icon: AnimatedBuilder(
                animation: _cardFlipController,
                builder: (_, _) => Icon(
                  _cardFlipController.value < 0.5
                      ? Icons.flip_rounded
                      : Icons.flip_camera_android_rounded,
                ),
              ),
              label: AnimatedBuilder(
                animation: _cardFlipController,
                builder: (_, _) => Text(
                  _cardFlipController.value < 0.5 ? 'View card back' : 'View card front',
                ),
              ),
            ),
            if (!_active) ...[
              const SizedBox(height: 4),
              Text(
                _membership == null
                ? 'Pay PHP 100 to activate your membership card.'
                    : 'Membership is ${'${_membership!['status'] ?? 'inactive'}'.toLowerCase()}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : (paymentPending ? _verifyPayment : _startPayment),
                icon: Icon(
                  paymentPending ? Icons.refresh_rounded : Icons.credit_card_rounded,
                ),
                label: Text(
                  paymentPending ? 'Check payment status' : 'Get membership - PHP 100',
                ),
              ),
              if (paymentPending && latestPayment['checkout_url'] != null)
                TextButton(
                  onPressed: _startPayment,
                  child: const Text('Open payment page again'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _membershipCardFront({
    required double width,
    required double height,
    required String memberId,
    required String memberSince,
  }) {
    final status = _active
        ? 'ACTIVE MEMBER'
        : (_membership == null
              ? 'NOT ACTIVE'
              : '${_membership!['status'] ?? 'PENDING'}'.toUpperCase());
    final scale = (width / 420).clamp(0.72, 1.5).toDouble();
    final userName = '${Api.I.user?['name'] ?? 'Customer'}';

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/card.png',
          fit: BoxFit.fill,
          errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF3B1E12)),
        ),
        // Cover the artwork's decorative tier text with the real membership state.
        Positioned(
          left: width * .65,
          top: height * .275,
          width: width * .30,
          height: height * .13,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: width * .012,
                vertical: height * .008,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF4A210B),
                border: Border.all(color: const Color(0xFFFFD77A), width: 1.2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status,
                maxLines: 1,
                style: TextStyle(
                  color: const Color(0xFFFFE3A0),
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                  fontSize: 11 * scale,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: width * .055,
          top: height * .51,
          width: width * .47,
          height: height * .45,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width * .47,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFFFE6AE),
                      fontWeight: FontWeight.w900,
                      fontSize: 17 * scale,
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                  ),
                  SizedBox(height: height * .008),
                  Text(
                    'MEMBER ID  $memberId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: height * .008),
                  Text(
                    '${_active ? _points : 0} POINTS',
                    maxLines: 1,
                    style: TextStyle(
                      color: const Color(0xFFFFD477),
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'MEMBER SINCE  $memberSince',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Replace the artwork's sample QR with the customer's real member QR.
        Positioned(
          left: width * .55,
          top: height * .485,
          width: width * .185,
          height: height * .425,
          child: Container(
            padding: EdgeInsets.all(width * .009),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _active
                ? QrImageView(
                    data: memberId,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                  )
                : Icon(
                    Icons.lock_outline_rounded,
                    color: const Color(0xFF603516),
                    size: width * .07,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _membershipCardBack() => Image.asset(
    'assets/images/card1.png',
    fit: BoxFit.fill,
    errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFF3E4C8)),
  );

  String _formatMemberSince(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Pending activation';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
  Widget _metricCard(String title, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      ]),
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
  );

  Widget _rewardCard(Map<String, dynamic> reward) {
    final cost = (reward['points_cost'] as num?)?.toInt() ?? 0;
    final available = _active && _points >= cost && !_busy;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [
        SizedBox(width: 92, height: 100, child: (reward['image_url'] ?? '').toString().isNotEmpty ? NetImage(reward['image_url']?.toString()) : const Icon(Icons.card_giftcard_rounded, size: 40)),
        Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${reward['name'] ?? 'Reward'}', style: const TextStyle(fontWeight: FontWeight.w800)),
          if ((reward['description'] ?? '').toString().isNotEmpty) Text('${reward['description']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 4),
          Text('$cost points', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
        ]))),
        Padding(padding: const EdgeInsets.only(right: 10), child: FilledButton(onPressed: available ? () => _redeem(reward) : null, child: const Text('Redeem'))),
      ]),
    );
  }

  Widget _redemptionRow(Map<String, dynamic> row) => Card(
    child: ListTile(
      leading: const Icon(Icons.redeem_rounded),
      title: Text('${row['reward_name'] ?? 'Reward'}'),
      subtitle: Text('${row['code'] ?? ''} Â· ${row['points_spent'] ?? 0} points'),
      trailing: Text('${row['status'] ?? 'pending'}'.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
      onTap: () => _showRedemption(row),
    ),
  );

  Widget _transactionRow(Map<String, dynamic> row) {
    final points = (row['points'] as num?)?.toInt() ?? 0;
    final date = DateTime.tryParse('${row['created_at']}')?.toLocal();
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(points >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline, color: points >= 0 ? Colors.green : Colors.deepOrange),
        title: Text('${row['description'] ?? row['type'] ?? 'Points activity'}'),
        subtitle: Text('${row['order_number'] ?? ''}${date == null ? '' : ' Â· ${date.month}/${date.day}/${date.year}'}'),
        trailing: Text('${points > 0 ? '+' : ''}$points', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  final String text;
  const _EmptyNotice(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  );
}
