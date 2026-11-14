import 'package:flutter_test/flutter_test.dart';

import 'package:coffee_customer/main.dart';

void main() {
  testWidgets('shows the KJM coffee splash branding', (tester) async {
    await tester.pumpWidget(const KjmApp());
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('COFFEE SHOP'), findsOneWidget);
    expect(find.text('Brewing coffee...'), findsNothing);
  });
}
