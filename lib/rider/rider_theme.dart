import 'package:flutter/material.dart';

/// Rider theme accent color.
const riderGreen = Color(0xFF176B67);

Color riderAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF75D3C8)
    : riderGreen;

String deliveryStatusLabel(String s) {
  switch (s) {
    case 'assigned':
      return 'New assignment';
    case 'accepted':
      return 'Accepted';
    case 'picked_up':
      return 'Order picked up';
    case 'on_the_way':
      return 'On the way';
    case 'declined':
      return 'Declined';
    case 'delivered':
      return 'Delivered';
    default:
      return s;
  }
}

Color deliveryStatusColor(String s) {
  switch (s) {
    case 'assigned':
      return Colors.amber.shade800;
    case 'accepted':
      return Colors.blue.shade700;
    case 'declined':
      return Colors.red.shade700;
    case 'picked_up':
      return Colors.indigo;
    case 'on_the_way':
      return Colors.purple;
    case 'delivered':
      return const Color(0xFF3C8D5A);
    default:
      return Colors.grey;
  }
}
