import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_colors.dart';
import 'package:proteinix/widgets/ui/logo_bloom.dart';
import 'package:proteinix/widgets/ui/progress_ring.dart';

const _rings = [
  RingSpec(label: 'Steps', current: 7400, goal: 10000, color: AppColors.secondary),
  RingSpec(label: 'Macros', current: 0.62, goal: 1, color: AppColors.primary),
  RingSpec(label: 'Water', current: 1800, goal: 2500, color: AppColors.water),
  RingSpec(label: 'Sleep', current: 6.4, goal: 8, color: AppColors.tertiary),
];

Future<void> pumpBloom(
  WidgetTester tester, {
  List<RingSpec> rings = _rings,
  VoidCallback? onComplete,
  Duration duration = const Duration(milliseconds: 600),
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: LogoBloom(
            rings: rings,
            duration: duration,
            onComplete: onComplete,
          ),
        ),
      ),
    ));

void main() {
  // The splash routes off the back of this callback rather than a fixed delay,
  // so a bloom that never reports finished is a launch that never proceeds.
  testWidgets('reports completion so the splash can route', (tester) async {
    var done = false;
    await pumpBloom(tester, onComplete: () => done = true);

    expect(done, isFalse, reason: 'not before it has played');
    await tester.pump(const Duration(milliseconds: 300));
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    expect(done, isTrue);
  });

  // Signed out, or a cold Hive cache: the mark should still bloom rather than
  // the launch screen rendering nothing at all.
  testWidgets('paints with no rings at all', (tester) async {
    await pumpBloom(tester, rings: const []);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  // Fewer rings than the mark has arcs — the painter walks four arcs and must
  // not index past the list it was handed.
  testWidgets('paints with fewer rings than arcs', (tester) async {
    await pumpBloom(tester, rings: _rings.take(2).toList());
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives an unmeasured ring', (tester) async {
    await pumpBloom(tester, rings: const [
      RingSpec(
          label: 'Sleep',
          current: 0,
          goal: 8,
          color: AppColors.tertiary,
          hasData: false),
    ]);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  // A goal of zero would make ratio divide by it.
  testWidgets('survives a zero goal', (tester) async {
    await pumpBloom(tester, rings: const [
      RingSpec(label: 'Steps', current: 500, goal: 0, color: AppColors.secondary),
    ]);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  // Disposal mid-flight is the ordinary case: the hard timeout in the splash
  // can route away while the controller is still running.
  testWidgets('disposing mid-animation does not throw', (tester) async {
    await pumpBloom(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
