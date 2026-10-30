import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/realtime.dart';

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
  Timer? _poller;
  StreamSubscription<Map<String, dynamic>>? _live;
  Map<String, dynamic>? _peer;
  int? _conversationId;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  bool _closed = false;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
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
        _messages
          ..clear()
          ..addAll(nextMessages);
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
          _error = error.message;
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

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending || _closed) return;
    setState(() => _sending = true);
    try {
      final data = widget.isRider
          ? await Api.I.sendRiderChatMessage(
              deliveryId: widget.targetId,
              body: body,
            )
          : await Api.I.sendCustomerRiderChatMessage(
              orderId: widget.targetId,
              body: body,
            );
      if (!mounted) return;
      _input.clear();
      _replaceMessages(data);
      _scrollToBottom();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Message was not sent. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _replaceMessages(Map<String, dynamic> data) {
    final peerValue = data[widget.isRider ? 'customer' : 'rider'];
    final values = data['messages'];
    setState(() {
      _conversationId = (data['conversation_id'] as num?)?.toInt();
      if (peerValue is Map) _peer = Map<String, dynamic>.from(peerValue);
      _messages
        ..clear()
        ..addAll(
          values is List
              ? values.whereType<Map>().map(
                  (item) => Map<String, dynamic>.from(item),
                )
              : const <Map<String, dynamic>>[],
        );
      _error = null;
    });
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
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
      body: Column(
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
                ? const Center(child: CircularProgressIndicator())
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
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  message['body']?.toString() ?? '',
                                  style: TextStyle(
                                    color: mine
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                        : null,
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
                    Expanded(
                      child: TextField(
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
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send message',
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
