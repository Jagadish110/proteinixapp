import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/utils/food_icon_resolver.dart';

/// A category with no SVG on disk throws when its row paints, so the set is
/// checked here rather than discovered in production.
void main() {
  for (final style in FoodIconStyle.values) {
    test('every category has a ${style.name} icon', () {
      final missing = [
        for (final category in FoodCategory.values)
          if (!File(category.assetFor(style)).existsSync()) category.name,
      ];
      expect(missing, isEmpty);
    });
  }

  test('icon files are non-empty SVGs', () {
    final bad = <String>[];
    for (final style in FoodIconStyle.values) {
      for (final category in FoodCategory.values) {
        final path = category.assetFor(style);
        final file = File(path);
        if (!file.existsSync()) continue;
        if (!file.readAsStringSync().contains('<svg')) bad.add(path);
      }
    }
    expect(bad, isEmpty);
  });

  test('pubspec declares both icon directories', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final style in FoodIconStyle.values) {
      expect(pubspec, contains('assets/icons/food/${style.name}/'));
    }
  });

  test('OpenMoji attribution ships as an asset', () {
    final licence = File('assets/icons/food/LICENSE.txt');
    expect(licence.existsSync(), isTrue);
    expect(licence.readAsStringSync(), contains('CC BY-SA 4.0'));
  });

  // Existing on disk is not enough — main.dart reads this through rootBundle,
  // so an undeclared asset means the licence page throws when it is opened.
  testWidgets('attribution is loadable from the bundle', (tester) async {
    final text = await rootBundle.loadString('assets/icons/food/LICENSE.txt');
    expect(text, contains('OpenMoji'));
  });
}
