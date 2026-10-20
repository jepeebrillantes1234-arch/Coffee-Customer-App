import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _message = TextEditingController();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _picker = ImagePicker();
  final _scroll = ScrollController();
  Timer? _refreshTimer;
  Map<String, dynamic>? _conversation;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _orders = [];
  String? _guestUuid;
  String? _guestToken;
  String? _attachmentPath;
  String? _attachmentName;
  int? _orderId;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  bool get _guest => !Api.I.loggedIn;
  int? get _conversationId => int.tryParse('${_conversation?['id'] ?? ''}');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _message.dispose();
    _name.dispose();
    _contact.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_guest) {
        final prefs = await SharedPreferences.getInstance();
        _guestUuid = prefs.getString('support_guest_uuid');
        _guestToken = prefs.getString('support_guest_token');
        if (_guestUuid != null && _guestToken != null) {
          await _refreshMessages();
        }
      } else {
        _conversation = await Api.I.supportConversation();
        final orders = await Api.I.orders();
        _orders = orders;
        if (_conversation != null) await _refreshMessages();
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not connect to customer service. Please try again.';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _startRefreshing();
      }
    }
  }

  void _startRefreshing() {
    _refreshTimer?.cancel();
    if (_conversation == null) return;
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_sending) _refreshMessages(silent: true);
    });
  }

  Future<void> _refreshMessages({bool silent = false}) async {
    try {
      final data = _guest
          ? await Api.I.guestSupportConversationMessages(
              _guestUuid!,
              _guestToken!,
            )
          : await Api.I.supportConversationMessages(_conversationId!);
      if (!mounted) return;
      final conversation = data['conversation'];
      final messages = data['messages'];
      setState(() {
        if (conversation is Map) {
          _conversation = Map<String, dynamic>.from(conversation);
        }
        if (messages is List) {
          _messages = messages
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
        if (!silent) _error = null;
      });
      if (!silent) _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted && !silent) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _error = 'Could not load the conversation.');
      }
    }
  }

  Future<void> _startGuestChat() async {
    if (_name.text.trim().isEmpty || _contact.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name and a phone number or email so the admin can reply.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await Api.I.startGuestSupportConversation(
        name: _name.text.trim(),
        contact: _contact.text.trim(),
      );
      final conversation = Map<String, dynamic>.from(result['conversation'] as Map);
      _guestUuid = conversation['guest_uuid']?.toString();
      _guestToken = result['guest_token']?.toString();
      if (_guestUuid == null || _guestToken == null) {
        throw ApiException('The server could not open a secure support chat.');
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('support_guest_uuid', _guestUuid!);
      await prefs.setString('support_guest_token', _guestToken!);
      if (!mounted) return;
      setState(() => _conversation = conversation);
      await _refreshMessages();
      _startRefreshing();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start the support chat.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_outlined), title: const Text('Choose a photo'), onTap: () => Navigator.pop(context, 'image')),
          ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Choose a video'), onTap: () => Navigator.pop(context, 'video')),
          ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, 'camera')),
        ]),
      ),
    );
    if (choice == null) return;
    final XFile? file = switch (choice) {
      'image' => await _picker.pickImage(source: ImageSource.gallery, imageQuality: 82, maxWidth: 1600),
      'video' => await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 45)),
      _ => await _picker.pickImage(source: ImageSource.camera, imageQuality: 82, maxWidth: 1600),
    };
    if (file == null || !mounted) return;
    setState(() {
      _attachmentPath = file.path;
      _attachmentName = file.name;
    });
  }

  Future<void> _send() async {
    if (_message.text.trim().isEmpty && _attachmentPath == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (_conversation == null) {
        _conversation = await Api.I.startSupportConversation();
      }
      await Api.I.sendSupportMessage(
        conversationId: _conversationId!,
        body: _message.text,
        attachmentPath: _attachmentPath,
        orderId: _orderId,
        guestUuid: _guestUuid,
        guestToken: _guestToken,
      );
      _message.clear();
      if (mounted) setState(() {
        _attachmentPath = null;
        _attachmentName = null;
        _orderId = null;
      });
      await _refreshMessages();
      _startRefreshing();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Message could not be sent. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startNewChat() async {
    if (_guest) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('support_guest_uuid');
      await prefs.remove('support_guest_token');
      _guestUuid = null;
      _guestToken = null;
    }
    if (!mounted) return;
    setState(() {
      _conversation = null;
      _messages = [];
      _error = null;
    });
    _startRefreshing();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  Widget _guestForm() => ListView(padding: const EdgeInsets.all(24), children: [
    const SizedBox(height: 34),
    Icon(Icons.support_agent_rounded, size: 58, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 14),
    Text('Chat with Customer Service', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('You can contact us even if you cannot sign in. Never send your password or verification code.', textAlign: TextAlign.center),
    const SizedBox(height: 24),
    TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder())),
    const SizedBox(height: 12),
    TextField(controller: _contact, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Phone number or reachable email', border: OutlineInputBorder())),
    if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.red))),
    const SizedBox(height: 18),
    FilledButton.icon(onPressed: _sending ? null : _startGuestChat, icon: const Icon(Icons.chat_bubble_outline), label: Text(_sending ? 'Connecting…' : 'Start chat')),
  ]);

  Widget _bubble(Map<String, dynamic> item) {
    final sender = item['sender_type']?.toString() ?? 'customer';
    final mine = sender == 'customer';
    final assistant = sender == 'assistant';
    final colors = Theme.of(context).colorScheme;
    final attachment = item['attachment_url']?.toString();
    final mime = item['attachment_mime']?.toString() ?? '';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: mine ? colors.primaryContainer : assistant ? colors.secondaryContainer : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!mine) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(assistant ? 'KJM Assistant' : 'Customer Service', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colors.primary))),
          if (attachment != null && attachment.isNotEmpty)
            if (mime.startsWith('image/'))
              GestureDetector(onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(attachment, headers: _attachmentHeaders)))), child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(attachment, headers: _attachmentHeaders, width: 230, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Text('Image unavailable'))))
            else
              const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.videocam_outlined, size: 18), SizedBox(width: 5), Text('Video attachment')]),
          if ((item['body']?.toString() ?? '').isNotEmpty) Text(item['body'].toString()),
          const SizedBox(height: 3),
          Text(item['created_at']?.toString() ?? '', style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Map<String, String> get _attachmentHeaders => _guest
      ? {'X-Support-Token': _guestToken ?? ''}
      : {'Authorization': 'Bearer ${Api.I.accessToken ?? ''}'};

  Widget _chat() => Column(children: [
    if (_error != null) Material(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red)))),
    Expanded(child: _messages.isEmpty ? const Center(child: Text('Send a message to start. An automated assistant will reply first, then an admin can join.')) : ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), children: _messages.map(_bubble).toList())),
    if (!_guest && _orders.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(12, 3, 12, 3), child: DropdownButtonFormField<int?>(initialValue: _orderId, isExpanded: true, decoration: const InputDecoration(labelText: 'Related order (optional)', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 7), border: OutlineInputBorder()), items: [const DropdownMenuItem<int?>(value: null, child: Text('No order selected')), ..._orders.map((o) => DropdownMenuItem<int?>(value: int.tryParse('${o['id']}'), child: Text('${o['order_number'] ?? 'Order'} · ${o['status'] ?? ''}', overflow: TextOverflow.ellipsis)))], onChanged: (value) => setState(() => _orderId = value))),
    if (_attachmentName != null) ListTile(dense: true, leading: const Icon(Icons.attach_file), title: Text(_attachmentName!, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(onPressed: () => setState(() { _attachmentName = null; _attachmentPath = null; }), icon: const Icon(Icons.close))),
    SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      IconButton(onPressed: _sending ? null : _pickAttachment, tooltip: 'Attach a photo or video', icon: const Icon(Icons.attach_file)),
      Expanded(child: TextField(controller: _message, minLines: 1, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Write a message…', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11)), onSubmitted: (_) => _send())),
      const SizedBox(width: 6),
      IconButton.filled(onPressed: _sending ? null : _send, tooltip: 'Send', icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded)),
    ]))),
  ]);

  Widget _closedConversation() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_outline, size: 48),
        const SizedBox(height: 12),
        const Text('This conversation has been closed. Start a new chat if you still need help.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: _startNewChat, child: const Text('Start a new chat')),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Customer Service'), Text('Automated help and admin support', style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal))]), actions: [Padding(padding: const EdgeInsets.only(right: 14), child: Icon(Icons.circle, color: _conversation?['status'] == 'closed' ? Colors.grey : Colors.green, size: 10))]),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _conversation != null && _conversation?['status'] == 'closed'
            ? _closedConversation()
            : _conversation == null && _guest
                ? _guestForm()
                : _conversation == null
                    ? Column(children: [
                        if (_error != null) Padding(padding: const EdgeInsets.all(10), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                        const Expanded(child: Center(child: Text('Send your question below to open a support chat.'))),
                      ])
                    : _chat(),
    bottomNavigationBar: !_loading && !_guest && _conversation == null ? SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [IconButton(onPressed: _pickAttachment, icon: const Icon(Icons.attach_file)), Expanded(child: TextField(controller: _message, decoration: const InputDecoration(hintText: 'Write a message…', border: OutlineInputBorder()))), IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send))]))) : null,
  );
}
