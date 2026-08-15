import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:musik_app/app.dart';

void main() {
  testWidgets('MusikApp builds', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MusikApp()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Cold start is intentionally seamless: no Flutter logo or spinner.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
