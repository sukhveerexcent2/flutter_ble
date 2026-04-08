import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ble/src/widgets.dart';

void main() {
  testWidgets('StatusMessage renders provided text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusMessage(text: 'Bluetooth ready'),
        ),
      ),
    );

    expect(find.text('Bluetooth ready'), findsOneWidget);
  });
}
