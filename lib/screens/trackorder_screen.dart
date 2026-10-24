import 'package:flutter/material.dart';

import 'order_detail_screen.dart';

/// Canonical customer route for tracking an existing order.
///
/// Tracking UI and API updates remain in [OrderDetailScreen], avoiding a
/// second implementation of the existing order status and rider tracking.
class TrackOrderScreen extends StatelessWidget {
  final int orderId;

  const TrackOrderScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) => OrderDetailScreen(id: orderId);
}
