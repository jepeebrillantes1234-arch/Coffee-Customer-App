import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/util.dart';
import 'rider_theme.dart';

/// Patunay ng delivery: larawan + cash na natanggap (kung COD).
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
      final x = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1400,
      );
      if (x != null && mounted) setState(() => _photo = x);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open the camera. Allow camera access in Settings.',
        );
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
        setState(
          () => _error =
              'The cash received must cover the order total of ${peso(_total)}.',
        );
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
            _cod ? 'Delivered! Hand the cash to the shop staff.' : 'Delivered!',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entered = double.tryParse(_cash.text.trim());
    final differs = _cod && entered != null && (entered - _total).abs() > 0.009;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Proof')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${widget.order['order_number']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),

          // 1. LARAWAN
          const Text(
            '1. Photo of the delivered order',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Photograph the order with the customer or at the delivery address.',
            style: TextStyle(fontSize: 12.5, color: secondary),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _take,
            child: Container(
              height: 240,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _photo == null
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_camera, size: 48, color: riderGreen),
                          SizedBox(height: 6),
                          Text('Tap to take a photo'),
                        ],
                      ),
                    )
                  : Image.file(
                      File(_photo!.path),
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: _busy ? null : _take,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_photo == null ? 'Take photo' : 'Retake photo'),
          ),

          // 2. CASH
          if (_cod) ...[
            const SizedBox(height: 20),
            const Text(
              '2. Cash received',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Amount due from customer: ${peso(_total)}',
              style: TextStyle(fontSize: 12.5, color: secondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cash,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixText: '₱ ',
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
            if (differs)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '⚠ The order is recorded at ${peso(_total)}. Return any extra cash to the customer as change.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                    fontSize: 12.5,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Text(
                '💵 Hand the cash to the shop staff. The order will be completed after they receive the payment.',
                style: TextStyle(
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: success),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit delivery'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
