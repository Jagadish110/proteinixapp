import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/utils/food_icon_resolver.dart';
import 'package:proteinix/widgets/ui/food_icon.dart';

/// Existing on disk is not the same as being drawable — this pumps the real
/// OpenMoji SVGs through flutter_svg.
void main() {
  testWidgets('renders an SVG for a food name', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: FoodIcon(foodName: 'Chicken Biryani')),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every category draws without throwing', (tester) async {
    for (final category in FoodCategory.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SvgPicture.asset(category.assetFor(FoodIcon.style)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: category.name);
    }
  });
}
