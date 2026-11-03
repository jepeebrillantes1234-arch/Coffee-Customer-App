import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/util.dart';
import 'rider_theme.dart';

/// Confirms delivery using the existing photo and COD collection API.
class RiderProofScreen extends StatefulWidget {
  final int deliveryId;
  final Map<String, dynamic> order;

  const RiderProofScreen({
    super.key,
    required this.deliveryId,
    required this.order,
  });

  @override
  State<RiderProofScreen> createState() => _RiderProofScreenState();
}

class _RiderProofScreenState extends State<RiderProofScreen> {
  XFile? _photo;
  final _cash = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _cod =>
      widget.order['payment_method'] == 'cod' &&
      widget.order['payment_status'] != 'paid';
  double get _total => dbl(widget.order['total']);

  @override
  void initState() {
    super.initState();
    if (_cod) _cash.text = _total.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  Future<void> _take() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1400,
      );
      if (photo != null && mounted) setState(() => _photo = photo);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not open the camera. Allow camera access in Settings.';
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_photo == null) {
      setState(() => _error = 'Take a photo as delivery proof first.');
      return;
    }

    double? cash;
    if (_cod) {
      cash = double.tryParse(_cash.text.trim());
      if (cash == null || cash < _total) {
        setState(() {
          _error =
              'Cash received must cover the order total of ${peso(_total)}.';
        });
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.I.deliverWithProof(widget.deliveryId, _photo!.path, cash);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _cod
                ? 'Delivery submitted. Please hand the cash to shop staff.'
                : 'Delivery proof submitted successfully.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final received = double.tryParse(_cash.text.trim());
    final differs =
        _cod && received != null && (received - _total).abs() > .009;
    final secondary = riderSecondaryText(context);

    return RiderVisualTheme(
      child: Scaffold(
        appBar: AppBar(title: const Text('Delivery confirmation')),
        body: RiderImageBackground(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            children: [
              _sectionCard(
                context,
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_outlined, color: riderGold),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order ${widget.order['order_number'] ?? ''}',
                            style: TextStyle(
                              color: riderPrimaryText(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add a clear delivery photo${_cod ? ' and confirm the cash received' : ''}.',
                            style: TextStyle(color: secondary, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _sectionCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(
                      context,
                      '1. Delivery photo',
                      Icons.camera_alt_outlined,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Take a clear photo showing the order at the customer location.',
                      style: TextStyle(color: secondary, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _busy ? null : _take,
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _photo == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo_outlined,
                                    size: 42,
                                    color: riderAccent(context),
                                  ),
                                  const SizedBox(height: 9),
                                  Text(
                                    'No photo added',
                                    style: TextStyle(
                                      color: riderPrimaryText(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap the button below to open the camera',
                                    style: TextStyle(
                                      color: secondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              )
                            : Image.file(
                                File(_photo!.path),
                                fit: BoxFit.cover,
                                width: double.infinity,
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _busy ? null : _take,
                      icon: Icon(
                        _photo == null
                            ? Icons.photo_camera_outlined
                            : Icons.refresh_rounded,
                      ),
                      label: Text(
                        _photo == null ? 'Take delivery photo' : 'Retake photo',
                      ),
                    ),
                  ],
                ),
              ),
              if (_cod) ...[
                const SizedBox(height: 14),
                _sectionCard(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle(
                        context,
                        '2. Cash on delivery',
                        Icons.payments_outlined,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: riderMutedTeal,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Amount due',
                              style: TextStyle(
                                color: riderCoffee,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              peso(_total),
                              style: const TextStyle(
                                color: riderCoffee,
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _cash,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Cash received from customer',
                          prefixText: '₱ ',
                          prefixIcon: Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                          helperText: 'Enter the full amount handed to you.',
                        ),
                      ),
                      if (differs)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'The order total is ${peso(_total)}. Please return any extra cash as change.',
                            style: TextStyle(
                              color: riderPrimaryText(context),
                              height: 1.4,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: riderAccent(context),
                              size: 20,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Hand the collected COD cash to shop staff. Staff will confirm receipt separately.',
                                style: TextStyle(
                                  color: riderPrimaryText(context),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: riderGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  _busy ? 'Submitting proof…' : 'Submit delivery proof',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(BuildContext context, {required Widget child}) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  Widget _sectionTitle(BuildContext context, String title, IconData icon) =>
      Row(
        children: [
          Icon(icon, color: riderAccent(context)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: riderPrimaryText(context),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
}
