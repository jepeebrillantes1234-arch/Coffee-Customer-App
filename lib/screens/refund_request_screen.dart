import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';

class RefundRequestScreen extends StatefulWidget {
  const RefundRequestScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<RefundRequestScreen> createState() => _RefundRequestScreenState();
}

class _RefundRequestScreenState extends State<RefundRequestScreen> {
  static const _reasons = <String, String>{
    'quality_issue': 'Product quality issue',
    'missing_or_incorrect_items': 'Missing or incorrect items',
    'duplicate_payment': 'Duplicate payment',
    'order_issue': 'Issue with my order',
    'other': 'Other',
  };

  final _explanation = TextEditingController();
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final List<XFile> _photos = [];
  String? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _explanation.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 3) return;
    final photo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (photo != null && mounted) setState(() => _photos.add(photo));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await Api.I.submitRefundRequest(
        widget.orderId,
        reason: _reason!,
        explanation: _explanation.text.trim(),
        photoPaths: _photos.map((photo) => photo.path).toList(),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The request could not be sent. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Request a Refund')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.receipt_long_rounded, size: 42, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              'Tell us what happened',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Your request will be reviewed by the KJM Coffee Shop team. A refund is not confirmed until PayMongo verifies it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _reason,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      prefixIcon: Icon(Icons.help_outline),
                    ),
                    items: _reasons.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: _sending
                        ? null
                        : (value) => setState(() => _reason = value),
                    validator: (value) =>
                        value == null ? 'Choose a reason.' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _explanation,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Explanation',
                      hintText: 'Please include any details that can help us review your request.',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Please explain your request.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _sending || _photos.length >= 3
                        ? null
                        : _addPhoto,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('Add supporting photos (${_photos.length}/3)'),
                  ),
                  if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var i = 0; i < _photos.length; i++)
                          InputChip(
                            avatar: const Icon(Icons.image_outlined, size: 18),
                            label: Text('Photo ${i + 1}'),
                            onDeleted: _sending
                                ? null
                                : () => setState(() => _photos.removeAt(i)),
                          ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: colors.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _sending ? null : _submit,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _sending ? 'Submitting…' : 'Submit Refund Request',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
