import 'package:flutter/material.dart';

import 'support_chat_screen.dart';

Future<void> showCustomerServiceSheet(BuildContext context) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const SupportChatScreen()),
  );
}
