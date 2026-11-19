import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/error_ui.dart';
import '../core/realtime.dart';
import '../rider/rider_theme.dart';

/// Order-bound private conversation between a customer and assigned rider.
/// [targetId] is an order ID for customers and a delivery ID for riders.
class RiderChatScreen extends StatefulWidget {
  const RiderChatScreen({
    super.key,
    required this.targetId,
    required this.isRider,
  });

  final int targetId;
  final bool isRider;

  @override
  State<RiderChatScreen> createState() => _RiderChatScreenState();
}

class _RiderChatScreenState extends State<RiderChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <Map<String, dynamic>>[];
  final _picker = ImagePicker();
  Timer? _poller;
  StreamSubscription<Map<String, dynamic>>? _live;
  Map<String, dynamic>? _peer;
  int? _conversationId;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  bool _closed = false;
  bool _requesting = false;
  XFile? _selectedImage;

  @override
  void initState() {
    super.initState();
    if (!widget.isRider) {
      Realtime.I.activeCustomerRiderChatOrderId = widget.targetId;
    }
    _load();
    Realtime.I.connect();
    _live = Realtime.I.updates.listen((event) {
      final meta = event['meta'];
      if (event['kind'] == 'delivery_chat' &&
          meta is Map &&
          '${meta['conversation_id']}' == '$_conversationId') {
        _load(silent: true);
      }
    });
    _poller = Timer.periodic(const Duration(seconds: 7), (_) {
      if (mounted && !_closed) _load(silent: true);
    });
  }

  @override
  void dispose() {
    if (!widget.isRider &&
        Realtime.I.activeCustomerRiderChatOrderId == widget.targetId) {
      Realtime.I.activeCustomerRiderChatOrderId = null;
    }
    _poller?.cancel();
    _live?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_requesting) return;
    _requesting = true;
    try {
      final data = widget.isRider
          ? await Api.I.riderDeliveryChat(widget.targetId)
          : await Api.I.customerRiderChat(widget.targetId);
      if (!mounted) return;
      final peerValue = data[widget.isRider ? 'customer' : 'rider'];
      final messageValues = data['messages'];
      final nextMessages = messageValues is List
          ? messageValues
                .whereType<Map>()
                .map((message) => Map<String, dynamic>.from(message))
                .toList()
          : <Map<String, dynamic>>[];
      final oldCount = _messages.length;
      setState(() {
        _conversationId = (data['conversation_id'] as num?)?.toInt();
        _peer = peerValue is Map ? Map<String, dynamic>.from(peerValue) : null;
        _mergeMessages(nextMessages);
        _closed = !const {
          'assigned',
          'accepted',
          'picked_up',
          'on_the_way',
        }.contains(data['status']?.toString());
        _error = null;
        _loading = false;
      });
      if (nextMessages.length > oldCount) _scrollToBottom();
      if (_closed) _poller?.cancel();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.displayMessage;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not connect. Check your connection and retry.';
          _loading = false;
        });
      }
    } finally {
      _requesting = false;
    }
  }

  Future<void> _send({Map<String, dynamic>? retry}) async {
    if (_sending || _closed) return;
    final body = retry?['body']?.toString() ?? _input.text.trim();
    final imagePath =
        retry?['local_attachment_path']?.toString() ?? _selectedImage?.path;
    if (body.isEmpty && imagePath == null) return;
    final clientId =
        retry?['client_message_id']?.toString() ?? _newClientMessageId();
    if (retry == null) {
      setState(() {
        _messages.add({
          'client_message_id': clientId,
          'sender_id': Api.I.user?['id'],
          'body': body,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'local_attachment_path': imagePath,
          'local_status': 'sending',
        });
        _sending = true;
      });
      _input.clear();
      _selectedImage = null;
      _scrollToBottom();
    } else {
      setState(() {
        retry['local_status'] = 'sending';
        _sending = true;
      });
    }
    try {
      final data = widget.isRider
          ? await Api.I.sendRiderChatMessage(
              deliveryId: widget.targetId,
              body: body,
              clientMessageId: clientId,
              imagePath: imagePath,
            )
          : await Api.I.sendCustomerRiderChatMessage(
              orderId: widget.targetId,
              body: body,
              clientMessageId: clientId,
              imagePath: imagePath,
            );
      if (!mounted) return;
      final saved = data['message'];
      if (saved is Map) {
        final savedMessage = Map<String, dynamic>.from(saved);
        final index = _messages.indexWhere(
          (m) => m['client_message_id'] == clientId,
        );
        setState(() {
          _conversationId = (data['conversation_id'] as num?)?.toInt();
          if (index >= 0) {
            _messages[index] = {...savedMessage, 'local_status': 'sent'};
          } else {
            _messages.add({...savedMessage, 'local_status': 'sent'});
          }
        });
      }
      _scrollToBottom();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _messages.firstWhere(
            (m) => m['client_message_id'] == clientId,
          )['local_status'] = 'failed';
          _error = error.displayMessage;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.firstWhere(
            (m) => m['client_message_id'] == clientId,
          )['local_status'] = 'failed';
          _error = 'Message was not sent. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _mergeMessages(List<Map<String, dynamic>> incoming) {
    final merged = [..._messages];
    for (final message in incoming) {
      final index = merged.indexWhere(
        (existing) =>
            (message['client_message_id'] != null &&
                existing['client_message_id'] ==
                    message['client_message_id']) ||
            (message['id'] != null && existing['id'] == message['id']),
      );
      final previous = index < 0 ? null : merged[index];
      final value = {
        ...?previous,
        ...message,
        // A server message with this client ID confirms any local retry.
        'local_status': 'sent',
      };
      if (index < 0) {
        merged.add(value);
      } else {
        merged[index] = value;
      }
    }
    _messages
      ..clear()
      ..addAll(
        merged..sort(
          (a, b) => (a['id'] as num? ?? 0).compareTo(b['id'] as num? ?? 0),
        ),
      );
  }

  String _newClientMessageId() {
    final random = Random.secure();
    final hex = List.generate(32, (_) => random.nextInt(16).toRadixString(16));
    hex[12] = '4';
    hex[16] = ((int.parse(hex[16], radix: 16) & 3) | 8).toRadixString(16);
    final value = hex.join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-${value.substring(12, 16)}-${value.substring(16, 20)}-${value.substring(20)}';
  }

  Future<void> _pickImage() async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final size = await File(image.path).length();
      if (!mounted) return;
      if (size > 2 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photos must be 2 MB or smaller.')),
        );
        return;
      }
      setState(() => _selectedImage = image);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not select this photo.')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _peer?['name']?.toString().trim();
    final avatar = _peer?['avatar_url']?.toString();
    final title = name == null || name.isEmpty
        ? (widget.isRider ? 'Customer' : 'Delivery rider')
        : name;
    final screen = Scaffold(
      appBar: AppBar(
        backgroundColor: widget.isRider ? riderCoffee : null,
        foregroundColor: widget.isRider ? riderCream : null,
        iconTheme: widget.isRider
            ? const IconThemeData(color: riderCream)
            : null,
        automaticallyImplyLeading: !widget.isRider,
        leadingWidth: widget.isRider ? 104 : null,
        leading: widget.isRider
            ? Row(
                children: [
                  const SizedBox(width: 10),
                  riderLogoBadge(),
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ],
              )
            : null,
        titleSpacing: widget.isRider ? 0 : null,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              child: avatar == null || avatar.isEmpty
                  ? const Icon(Icons.person_outline_rounded, size: 20)
                  : ClipOval(
                      child: Image.network(
                        avatar,
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.person_outline_rounded, size: 20),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    widget.isRider ? 'Customer' : 'Assigned delivery rider',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: RiderImageBackground(
        enabled: widget.isRider,
        child: Column(
          children: [
            if (_error != null)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: Text(_error!),
                  trailing: IconButton(
                    tooltip: 'Retry',
                    onPressed: () => _load(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const KjmLoadingView()
                  : _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Start the conversation',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Messages here are only shared between the customer and assigned rider.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 18,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final mine =
                            '${message['sender_id']}' == '${Api.I.user?['id']}';
                        final time = DateTime.tryParse(
                          '${message['created_at'] ?? ''}',
                        )?.toLocal();
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * .78,
                            ),
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(mine ? 16 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (message['local_attachment_path'] != null ||
                                    message['attachment_url'] != null)
                                  GestureDetector(
                                    onTap: () => _showPhoto(message),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: _messagePhoto(message),
                                    ),
                                  ),
                                if ((message['body']?.toString() ?? '')
                                    .isNotEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      message['body'].toString(),
                                      style: TextStyle(
                                        color: mine
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary
                                            : null,
                                      ),
                                    ),
                                  ),
                                if (message['local_status'] == 'failed')
                                  TextButton.icon(
                                    onPressed: _sending
                                        ? null
                                        : () => _send(retry: message),
                                    icon: const Icon(Icons.refresh, size: 15),
                                    label: const Text('Failed · Retry'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: mine
                                          ? Theme.of(context)
                                                .colorScheme
                                                .onPrimary
                                          : Theme.of(context).colorScheme.error,
                                    ),
                                  )
                                else if (message['local_status'] == 'sending')
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Sending…',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                  )
                                else if (message['local_status'] == 'sent' &&
                                    mine)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Sent',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                            .withValues(alpha: .75),
                                      ),
                                    ),
                                  ),
                                if (time != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: mine
                                          ? Theme.of(context)
                                                .colorScheme
                                                .onPrimary
                                                .withValues(alpha: .75)
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_closed)
              const SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'This delivery conversation is closed.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Attach photo',
                        onPressed: _sending ? null : _pickImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_selectedImage != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(_selectedImage!.path),
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text('Photo ready to send'),
                                    ),
                                    IconButton(
                                      tooltip: 'Cancel photo',
                                      onPressed: _sending
                                          ? null
                                          : () => setState(
                                              () => _selectedImage = null,
                                            ),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                              ),
                            TextField(
                              controller: _input,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(
                                hintText: 'Write a message…',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Send message',
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return widget.isRider ? RiderVisualTheme(child: screen) : screen;
  }

  Widget _messagePhoto(Map<String, dynamic> message) {
    final localPath = message['local_attachment_path']?.toString();
    if (localPath != null && File(localPath).existsSync()) {
      return Image.file(
        File(localPath),
        width: 220,
        height: 180,
        fit: BoxFit.cover,
      );
    }
    final url = message['attachment_url']?.toString();
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Image.network(
      url,
      width: 220,
      height: 180,
      fit: BoxFit.cover,
      headers: Api.I.authenticatedHeaders,
      errorBuilder: (_, _, _) => const SizedBox(
        width: 220,
        height: 100,
        child: Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }

  void _showPhoto(Map<String, dynamic> message) {
    final size = MediaQuery.sizeOf(context);
    final localPath = message['local_attachment_path']?.toString();
    final url = message['attachment_url']?.toString();
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: size.width * .9,
          height: size.height * .78,
          child: InteractiveViewer(
            minScale: .7,
            maxScale: 4,
            child: localPath != null && File(localPath).existsSync()
                ? Image.file(
                    File(localPath),
                    fit: BoxFit.contain,
                    width: size.width * .9,
                    height: size.height * .78,
                  )
                : Image.network(
                    url ?? '',
                    headers: Api.I.authenticatedHeaders,
                    fit: BoxFit.contain,
                    width: size.width * .9,
                    height: size.height * .78,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
