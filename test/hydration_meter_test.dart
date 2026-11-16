import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_colors.dart';
import 'package:proteinix/widgets/ui/hydration_meter.dart';

Future<void> pumpTank(WidgetTester tester, double fill,
    {double width = 320, double height = 64}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: WaveTank(fill: fill),
        ),
      ),
    ),
  ));
  // Past the fill tween so the painter has run at the target value.
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  // The fill is drawn as a rounded rect whose radius is clamped to half its own
  // width and height. These are the fills where that clamp matters — an
  // unclamped radius on a nearly-empty tank renders a lens or nothing at all.
  group('paints at every fill', () {
    for (final fill in [0.0, 0.005, 0.03, 0.12, 0.5, 0.99, 1.0]) {
      testWidgets('fill $fill', (tester) async {
        await pumpTank(tester, fill);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Callers clamp, but the painter must not blow up if one ever doesn't.
  testWidgets('survives out-of-range fills', (tester) async {
    await pumpTank(tester, 1.6);
    expect(tester.takeException(), isNull);
    await pumpTank(tester, -0.4);
    expect(tester.takeException(), isNull);
  });

  // A short tank clamps the radius on height rather than width.
  testWidgets('paints in a very short tank', (tester) async {
    await pumpTank(tester, 0.6, height: 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paints in a very narrow tank', (tester) async {
    await pumpTank(tester, 0.6, width: 24);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card renders its volumes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HydrationCard(currentMl: 3000, goalMl: 2100, onAdd: (_) {}),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    // Over-goal clamps the bar but must still report the real intake.
    // findRichText, because the read-out is spans inside one RichText rather
    // than separate Text widgets.
    expect(find.textContaining('3,000', findRichText: true), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });
}
