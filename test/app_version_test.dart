import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/constants/strings.dart';

void main() {
  test('AppStrings.appVersion matches pubspec', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    // "version: 1.0.0+1" — the build number is not shown to users.
    final pubspecVersion = line.split(':')[1].trim().split('+').first;

    expect(AppStrings.appVersion, pubspecVersion);
  });
}
