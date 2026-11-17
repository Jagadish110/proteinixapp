import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_colors.dart';
import 'package:proteinix/core/theme/app_theme.dart';
import 'package:proteinix/models/daily_log.dart';
import 'package:proteinix/models/user_profile.dart';
import 'package:proteinix/screens/home/home_hero_card.dart';
import 'package:proteinix/widgets/ui/floating_nav_bar.dart';

/// The redesigned dashboard hero and nav bar at the sizes that actually ship.
/// A RenderFlex overflow fails these, which is the point: the hero lives in a
/// fixed-height carousel slot, so anything that grows past it is clipped on
/// a real phone without any error.

UserProfile profile({int calories = 2100, double protein = 110}) =>
    UserProfile(id: 'u1', calorieGoal: calories, proteinGoalG: protein);

DailyLog log({int calories = 1240, double protein = 62}) => DailyLog(
      userId: 'u1',
      date: DateTime(2026, 11, 17),
      caloriesConsumed: calories,
      proteinG: protein,
      carbsG: 148,
      fatG: 38,
      fiberG: 14,
    );

/// The home carousel slot: screen width minus the page gutters, and 312 px
/// grown with the text scale up to 1.4, as home_screen.dart sizes it.
Future<void> pumpHero(
  WidgetTester tester, {
  required Widget card,
  double screenWidth = 320,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(screenWidth * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final height = 312 * textScale.clamp(1.0, 1.4);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(screenWidth, 900),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(height: height, child: card),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('EnergyHeroCard', () {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('fits at ${width.toInt()}dp, text x$scale',
            (tester) async {
          await pumpHero(
            tester,
            screenWidth: width,
            textScale: scale,
            card: EnergyHeroCard(profile: profile(), log: log()),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('860'), findsOneWidget);
          expect(find.text('kcal left'), findsOneWidget);
          expect(find.text('48 g to go'), findsOneWidget);
        });
      }
    }

    testWidgets('says "over" rather than a negative number', (tester) async {
      await pumpHero(
        tester,
        card: EnergyHeroCard(
            profile: profile(), log: log(calories: 2400, protein: 120)),
      );
      expect(find.text('300'), findsOneWidget);
      expect(find.text('kcal over'), findsOneWidget);
      expect(find.text('Goal met'), findsOneWidget);
    });

    testWidgets('an empty day still renders', (tester) async {
      await pumpHero(
        tester,
        textScale: 1.3,
        card: EnergyHeroCard(profile: profile(), log: null),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('2,100'), findsOneWidget);
    });

    testWidgets('large goals fit the ring', (tester) async {
      await pumpHero(
        tester,
        textScale: 1.3,
        card: EnergyHeroCard(
          profile: profile(calories: 12000, protein: 300),
          log: log(calories: 0, protein: 0),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FloatingNavBar', () {
    const destinations = [
      NavDestination(icon: Icons.home_rounded, label: 'Home'),
      NavDestination(icon: Icons.restaurant_rounded, label: 'Nutrition'),
      NavDestination(icon: Icons.photo_camera_rounded, label: 'Capture'),
      NavDestination(icon: Icons.trending_up_rounded, label: 'Progress'),
      NavDestination(icon: Icons.smart_toy_rounded, label: 'Coach'),
    ];

    testWidgets('fits at 320dp and reports taps', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 700 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      int? selected;
      var captured = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          bottomNavigationBar: FloatingNavBar(
            destinations: destinations,
            currentIndex: 0,
            captureIndex: 2,
            onSelect: (i) => selected = i,
            onCapture: () => captured = true,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Coach'));
      expect(selected, 4);

      await tester.tap(find.bySemanticsLabel('Scan a meal'));
      expect(captured, isTrue);
    });

    testWidgets('every tab has an accessible name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          bottomNavigationBar: FloatingNavBar(
            destinations: destinations,
            currentIndex: 1,
            captureIndex: 2,
            onSelect: (_) {},
            onCapture: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      for (final label in ['Home', 'Nutrition', 'Progress', 'Coach']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Scan a meal'), findsOneWidget);
      handle.dispose();
    });
  });
}
