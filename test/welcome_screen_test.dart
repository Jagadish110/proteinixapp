import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/constants/strings.dart';
import 'package:proteinix/screens/auth/welcome_screen.dart';
import 'package:proteinix/widgets/ui/ui.dart';

const _backdrop = 'assets/images/welcome_bowls.jpg';

void main() {
  test('welcome backdrop is on disk and declared', () {
    expect(File(_backdrop).existsSync(), isTrue);
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/images/'));
  });

  // The screen reads this through the asset bundle, so an undeclared image
  // means a blank backdrop in a real build, not a test failure here.
  testWidgets('backdrop loads from the bundle', (tester) async {
    final bytes = await rootBundle.load(_backdrop);
    expect(bytes.lengthInBytes, greaterThan(0));
  });

  testWidgets('get started sits on the screen centre line', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.pump();

    expect(find.text(AppStrings.getStarted), findsOneWidget);

    // The button itself, not its label — the trailing arrow pulls the text a
    // few pixels off centre inside an otherwise centred pill.
    final button = find.byType(PillButton);
    final screenCentre = tester.getCenter(find.byType(Scaffold)).dx;
    expect(tester.getCenter(button).dx, moreOrLessEquals(screenCentre, epsilon: 1));
  });
}
