import 'package:coffee_customer/screens/payment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('order payment opens with its QR visible immediately', (
    tester,
  ) async {
    final order = <String, dynamic>{
      'id': 42,
      'order_number': 'KJM-TEST-QRPH',
      'order_type': 'pickup',
      'status': 'awaiting_payment',
      'payment_method': 'qrph',
      'payment_status': 'unpaid',
      'payment_attempt_status': 'pending',
      'payment_reference': 'KJM-TEST-QRPH',
      'qr_image_url':
          'data:image/png;base64,'
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAE0lEQVR4nGP8//8/AwMDEwMYAAAkBgMBXaJOiAAAAABJRU5ErkJggg==',
      'expires_at': DateTime.now()
          .add(const Duration(minutes: 30))
          .toIso8601String(),
      'total': 125.0,
    };

    await tester.pumpWidget(MaterialApp(home: PaymentScreen(order: order)));
    await tester.pump();

    expect(find.text('Pay with QRPh'), findsOneWidget);
    expect(find.text('KJM-TEST-QRPH'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );
    expect(find.text('View QR'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
