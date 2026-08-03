import 'package:blocpod_sample/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sample app panels dispatch events and show live logs', (tester) async {
    await tester.pumpWidget(const BlocpodSampleApp());

    expect(find.text('Counter events'), findsOneWidget);
    expect(find.text('UseCase and Result'), findsOneWidget);
    expect(find.text('Provider variants'), findsOneWidget);
    expect(find.text('Event log'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '+1'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '+1'));
    await tester.pump();

    expect(find.text('Count: 2'), findsOneWidget);
    expect(
      _textContaining('✅ SampleCounterController · CounterIncremented completed'),
      findsAtLeastNWidgets(1),
    );

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Load todos'));
    await tester.tap(find.widgetWithText(FilledButton, 'Load todos'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Add todo'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add todo'));
    await tester.pump();

    expect(find.text('Read Blocpod architecture'), findsOneWidget);
    expect(find.text('Try Blocpod'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Regular'));
    await tester.tap(find.widgetWithText(FilledButton, 'Regular'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Regular'));
    await tester.pump();

    expect(find.text('Regular: 2'), findsOneWidget);
    expect(_textContaining('VariantCounterController'), findsAtLeastNWidgets(1));
    expect(_textContaining('providerName='), findsNothing);
    expect(_textContaining('providerKind='), findsNothing);
    expect(_textContaining('sequence='), findsNothing);
  });
}

Finder _textContaining(String value) {
  return find.byWidgetPredicate((widget) => widget is Text && widget.data?.contains(value) == true);
}
