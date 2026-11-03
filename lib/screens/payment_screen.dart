import 'package:flutter/material.dart';

import 'qrph_payment_screen.dart';

/// Payment screen entry point retained for the existing order checkout flow.
class PaymentScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const PaymentScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) => QrphPaymentScreen.order(order: order);
}
