import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_manager/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ServerManagerApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
