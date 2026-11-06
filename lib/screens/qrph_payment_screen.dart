import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/util.dart';
import '../core/widgets.dart' show fixUrl;
import 'trackorder_screen.dart';

enum _PaymentKind { order, membership }

enum _PaymentPhase { pending, failed, expired, success }

/// In-app QRPh payment UI shared by product orders and membership payments.
/// Only server-confirmed payment fields can move this screen to success.
class QrphPaymentScreen extends StatefulWidget {
  final _PaymentKind _kind;
  final Map<String, dynamic>? order;
  final Map<String, dynamic>? checkout;

  const QrphPaymentScreen.order({required this.order})
    : _kind = _PaymentKind.order,
      checkout = null,
      super(key: const ValueKey('order-qrph-payment'));

  const QrphPaymentScreen.membership({required this.checkout})
    : _kind = _PaymentKind.membership,
      order = null,
      super(key: const ValueKey('membership-qrph-payment'));

  @override
  State<QrphPaymentScreen> createState() => _QrphPaymentScreenState();
}

class _QrphPaymentScreenState extends State<QrphPaymentScreen>
    with WidgetsBindingObserver {
  late Map<String, dynamic> _payment;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  DateTime? _expiresAt;
  Duration _remaining = Duration.zero;
  _PaymentPhase _phase = _PaymentPhase.pending;
  bool _busy = false;
  bool _checking = false;
  bool _legacyCheckoutOpened = false;
  double? _paidAmount;
  String? _paidReference;
  String? _paidAt;

  bool get _isOrder => widget._kind == _PaymentKind.order;
  int get _orderId => (widget.order?['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _payment = Map<String, dynamic>.from(
      widget._kind == _PaymentKind.order ? widget.order! : widget.checkout!,
    );
    _applyPaymentData(_payment);
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateCountdown(),
    );
    _startPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isOrder && _imageValue.isEmpty) {
        _retryPayment();
      } else {
        _openLegacyCheckoutIfNeeded();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _phase == _PaymentPhase.pending) {
      _checkStatus(manual: true);
    }
  }

  String get _imageValue => '${_payment['qr_image_url'] ?? ''}'.trim();

  String get _reference =>
      '${_payment['payment_reference'] ?? _payment['order_number'] ?? _payment['payment']?['payment_reference'] ?? ''}';

  double get _amount {
    final value =
        _payment['amount'] ??
        _payment['payment_amount'] ??
        _payment['payment']?['amount'] ??
        widget.order?['total'];
    return value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  }

  bool get _hasExpired =>
      _phase == _PaymentPhase.expired ||
      (_expiresAt != null && !_expiresAt!.isAfter(DateTime.now()));

  void _applyPaymentData(Map<String, dynamic> data) {
    _payment = Map<String, dynamic>.from(data);
    final expires =
        data['expires_at'] ??
        data['qr_expires_at'] ??
        data['payment_expires_at'] ??
        (data['payment'] is Map ? data['payment']['qr_expires_at'] : null);
    _expiresAt = DateTime.tryParse('$expires')?.toLocal();
    final rawPhase = '${data['payment_attempt_status'] ?? data['status'] ?? ''}'
        .toLowerCase();
    final providerPhase = '${data['provider_status'] ?? ''}'.toLowerCase();
    if (rawPhase == 'failed' ||
        rawPhase == 'cancelled' ||
        providerPhase == 'failed' ||
        providerPhase == 'cancelled') {
      _phase = _PaymentPhase.failed;
    } else if (rawPhase == 'expired') {
      _phase = _PaymentPhase.expired;
    } else if (_phase != _PaymentPhase.success) {
      _phase = _PaymentPhase.pending;
    }
    _updateCountdown(setStateAfter: false);
  }

  void _updateCountdown({bool setStateAfter = true}) {
    if (_expiresAt == null || _phase == _PaymentPhase.success) return;
    final next = _expiresAt!.difference(DateTime.now());
    final remaining = next.isNegative ? Duration.zero : next;
    if (remaining == Duration.zero && _phase == _PaymentPhase.pending) {
      _phase = _PaymentPhase.expired;
    }
    if (setStateAfter && mounted) setState(() => _remaining = remaining);
    _remaining = remaining;
  }

  String get _countdownText {
    final minutes = _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = _remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _retryPayment() async {
    if (_busy || _phase == _PaymentPhase.success) return;
    setState(() => _busy = true);
    try {
      final data = _isOrder
          ? await Api.I.payOrder(_orderId)
          : await Api.I.startMembershipCheckout();
      if (!mounted) return;
      setState(() {
        _phase = _PaymentPhase.pending;
        _applyPaymentData(data);
      });
      _startPolling();
      await _openLegacyCheckoutIfNeeded();
      if (_imageValue.isEmpty && !_hasLegacyCheckout) {
        _message('A QR code is not available yet. Please try again.');
      }
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _hasLegacyCheckout =>
      '${_payment['checkout_url'] ?? _payment['url'] ?? ''}'.trim().isNotEmpty;

  Future<void> _openLegacyCheckoutIfNeeded({bool force = false}) async {
    if (_imageValue.isNotEmpty || !_hasLegacyCheckout) return;
    if (force) _legacyCheckoutOpened = false;
    if (_legacyCheckoutOpened) return;
    _legacyCheckoutOpened = true;
    final value = '${_payment['checkout_url'] ?? _payment['url']}';
    final uri = Uri.tryParse(fixUrl(value));
    if (uri == null) {
      _message('The legacy payment page link is invalid.');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _message('Could not open the legacy payment page.');
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Keep checking after the local QR timer reaches zero. Laravel remains
    // authoritative and may receive a valid payment webhook at the deadline.
    if (_phase == _PaymentPhase.pending || _phase == _PaymentPhase.expired) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkStatus(),
      );
    }
  }

  Future<void> _checkStatus({bool manual = false}) async {
    if (_checking || _busy || _phase == _PaymentPhase.success) return;
    _checking = true;
    try {
      final result = _isOrder
          ? await Api.I.verifyPayment(_orderId)
          : await Api.I.verifyMembershipPayment();
      if (!mounted) return;
      if (_isServerConfirmed(result)) {
        _showSuccess(result);
      } else if (_isOrder &&
          '${result['status']}'.toLowerCase() == 'cancelled') {
        setState(() => _phase = _PaymentPhase.failed);
        _pollTimer?.cancel();
        if (manual) {
          _message('This order was cancelled before payment was confirmed.');
        }
      } else {
        if (!_isOrder) {
          final membership = result['membership'];
          final latestPayment = membership is Map
              ? membership['latest_payment']
              : null;
          if (latestPayment is Map) {
            final paymentStatus = '${latestPayment['status']}'.toLowerCase();
            if (paymentStatus == 'failed' || paymentStatus == 'cancelled') {
              setState(() => _phase = _PaymentPhase.failed);
              _pollTimer?.cancel();
            } else if (paymentStatus == 'expired') {
              setState(() => _phase = _PaymentPhase.expired);
              _pollTimer?.cancel();
            }
          }
        }
        if (manual) _message('Payment is still pending confirmation.');
      }
    } on ApiException catch (error) {
      if (manual) _message(error.message);
    } finally {
      _checking = false;
    }
  }

  bool _isServerConfirmed(Map<String, dynamic> result) {
    if (_isOrder) {
      return '${result['payment_status']}'.toLowerCase() == 'paid';
    }
    final membership = result['membership'];
    final latestPayment = membership is Map
        ? membership['latest_payment']
        : null;
    return membership is Map &&
        membership['active'] == true &&
        latestPayment is Map &&
        '${latestPayment['status']}'.toLowerCase() == 'paid';
  }

  void _showSuccess(Map<String, dynamic> result) {
    final paidAt = _isOrder
        ? result['payment_paid_at']
        : (result['membership'] as Map)['latest_payment']['paid_at'];
    final ref = _isOrder
        ? (result['payment_reference'] ?? _reference)
        : (result['membership'] as Map)['latest_payment']['payment_reference'];
    final amount = _isOrder
        ? (result['payment_amount'] ?? result['total'] ?? _amount)
        : (result['membership'] as Map)['latest_payment']['amount'];
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    setState(() {
      _phase = _PaymentPhase.success;
      _paidAt = paidAt?.toString();
      _paidReference = ref?.toString() ?? _reference;
      _paidAmount = amount is num
          ? amount.toDouble()
          : double.tryParse('$amount') ?? _amount;
    });
  }

  Future<void> _continue() async {
    if (_isOrder) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TrackOrderScreen(orderId: _orderId)),
      );
    } else {
      Navigator.of(context).pop(true);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _cancelOrder() async {
    if (!_isOrder || _busy || _phase == _PaymentPhase.success) return;
    final controller = TextEditingController();
    final key = GlobalKey<FormState>();
    String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancel this order?'),
          content: Form(
            key: key,
            child: TextFormField(
              controller: controller,
              minLines: 2,
              maxLines: 4,
              maxLength: 255,
              decoration: const InputDecoration(
                labelText: 'Cancellation reason',
                hintText: 'Tell us why you need to cancel',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Please enter a reason for cancellation.'
                  : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep order'),
            ),
            FilledButton(
              onPressed: () {
                if (key.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('Yes, cancel'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await Api.I.cancel(_orderId, reason: reason);
      _pollTimer?.cancel();
      _countdownTimer?.cancel();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _qrImage(BuildContext context) {
    final value = _imageValue;
    if (value.startsWith('data:image/')) {
      final comma = value.indexOf(',');
      if (comma >= 0) {
        try {
          return Image.memory(
            base64Decode(value.substring(comma + 1)),
            fit: BoxFit.contain,
          );
        } on FormatException {
          // Fall through to the unavailable state below.
        }
      }
    } else if (value.startsWith('https://') || value.startsWith('http://')) {
      return Image.network(
        fixUrl(value),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _qrUnavailable(context),
      );
    }
    return _qrUnavailable(context);
  }

  Widget _qrUnavailable(BuildContext context) => Center(
    child: Icon(
      Icons.qr_code_2_rounded,
      size: 84,
      color: Theme.of(context).colorScheme.primary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_phase == _PaymentPhase.success) return _successView(context);
    final expired = _hasExpired;
    final failed = _phase == _PaymentPhase.failed;
    final needsRetry = expired || failed || _imageValue.isEmpty;
    final statusLabel = failed
        ? 'Payment failed'
        : expired
        ? 'QR expired'
        : 'Waiting for payment';
    final statusColor = failed || expired ? colors.error : colors.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isOrder ? 'Order Payment' : 'Membership Payment'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 276,
              height: 276,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: _qrImage(context),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Image.asset(
              'assets/images/qrph.png',
              width: 58,
              height: 36,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.qr_code_2_rounded,
                size: 32,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pay with QRPh',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (_isOrder && widget.order?['order_number'] != null) ...[
            const SizedBox(height: 4),
            Text(
              '${widget.order!['order_number']}',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(
                    'Amount due',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    peso(_amount),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  _detailLine(
                    context,
                    'Reference',
                    _reference.isEmpty ? 'Not available' : _reference,
                  ),
                  if (_expiresAt != null)
                    _detailLine(
                      context,
                      'QR expiry',
                      expired ? 'Expired' : _countdownText,
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _imageValue.isEmpty
                ? 'The QR code is not available. You can retry or check the payment status.'
                : 'Scan this QR code using a QRPh-enabled wallet or banking app. This screen will update after Laravel confirms payment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (_hasLegacyCheckout)
            OutlinedButton.icon(
              onPressed: () => _openLegacyCheckoutIfNeeded(force: true),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open legacy payment page'),
            ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : (needsRetry
                      ? _retryPayment
                      : () => _checkStatus(manual: true)),
            icon: _busy || _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    expired || failed
                        ? Icons.refresh_rounded
                        : Icons.sync_rounded,
                  ),
            label: Text(needsRetry ? 'Retry Payment' : 'Check Status'),
          ),
          if (needsRetry)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: _busy || _checking
                    ? null
                    : () => _checkStatus(manual: true),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Check Status'),
              ),
            ),
          if (_isOrder && widget.order?['status'] == 'awaiting_payment')
            TextButton(
              onPressed: _busy ? null : _cancelOrder,
              child: Text(
                'Cancel order',
                style: TextStyle(color: colors.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailLine(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  Widget _successView(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = DateTime.tryParse(_paidAt ?? '')?.toLocal();
    final formattedDate = date == null
        ? 'Not available'
        : '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Complete'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: .55, end: 1),
              duration: const Duration(milliseconds: 550),
              curve: Curves.elasticOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: CircleAvatar(
                radius: 52,
                backgroundColor: Colors.green.shade600,
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 58,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Payment Successful!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Your payment has been confirmed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            if (!_isOrder) ...[
              const SizedBox(height: 8),
              Text(
                'Your Membership is Now Active.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _detailLine(
                      context,
                      'Amount paid',
                      peso(_paidAmount ?? _amount),
                    ),
                    _detailLine(
                      context,
                      'Reference',
                      _paidReference ?? 'Not available',
                    ),
                    _detailLine(context, 'Transaction date', formattedDate),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: _continue,
              child: Text(_isOrder ? 'Continue to Order Tracking' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
