import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_colors.dart';
import 'package:proteinix/core/theme/app_theme.dart';
import 'package:proteinix/providers/subscription_provider.dart';
import 'package:proteinix/screens/home/home_prompts.dart';
import 'package:proteinix/screens/log/routine_sheets.dart';
import 'package:proteinix/services/routine_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The new sheets and cards, pumped at the narrowest phone width and a large
/// text scale. A RenderFlex overflow fails the test, which is the point: these
/// are the screens that cannot be checked by eye before a release build.

SavedRoutine rajma() => SavedRoutine(
      id: 'r1',
      name: "Mum's rajma chawal with extra onions",
      createdAt: DateTime(2026, 1, 1),
      items: const [
        RoutineItem(
          name: 'Rajma',
          quantity: 1,
          unit: 'katori',
          calories: 240,
          proteinG: 12,
          carbsG: 34,
          fatG: 6,
          fiberG: 9,
        ),
        RoutineItem(
          name: 'Rice',
          quantity: 150,
          unit: 'g',
          calories: 195,
          proteinG: 4,
          carbsG: 42,
          fatG: 0.5,
          fiberG: 0.6,
        ),
      ],
    );

Future<void> pumpHost(
  WidgetTester tester,
  Widget child, {
  double width = 320,
  double textScale = 1.3,
}) async {
  tester.view.physicalSize = Size(width * 3, 760 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [isPremiumProvider.overrideWith((ref) => false)],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: Scaffold(backgroundColor: AppColors.background, body: child),
    ),
  ));
}

void main() {
  testWidgets('portion sheet fits, and returns the chosen multiplier',
      (tester) async {
    double? picked;
    await pumpHost(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            picked = await showPortionSheet(context,
                routine: rajma(), mealLabel: 'Mid-morning snack');
          },
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 1 portion by default: 240 + 195.
    expect(find.textContaining('435 kcal'), findsOneWidget);

    await tester.tap(find.text('1½'));
    await tester.pumpAndSettle();
    // 360 + 293 (292.5 rounds up per item).
    expect(find.textContaining('653 kcal'), findsOneWidget);

    await tester.tap(find.text('Add to Mid-morning snack'));
    await tester.pumpAndSettle();
    expect(picked, 1.5);
  });

  testWidgets('own-dish sheet fits and refuses an unusable dish',
      (tester) async {
    await pumpHost(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showOwnDishSheet(context, uid: 'u1'),
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add your own dish'), findsOneWidget);

    // No name yet.
    await tester.tap(find.text('Save dish'));
    await tester.pumpAndSettle();
    expect(find.text('Give the dish a name.'), findsOneWidget);

    // A name but no calories.
    await tester.enterText(find.byType(TextField).first, 'Rajma');
    await tester.tap(find.text('Save dish'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the calories in one portion.'), findsOneWidget);
    // Still open — nothing was saved.
    expect(find.text('Add your own dish'), findsOneWidget);
  });

  testWidgets('welcome-back card appears after missed days and dismisses',
      (tester) async {
    final lastOpen = DateTime.now().subtract(const Duration(days: 4));
    final iso = '${lastOpen.year.toString().padLeft(4, '0')}-'
        '${lastOpen.month.toString().padLeft(2, '0')}-'
        '${lastOpen.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({'last_open_day': iso});

    await pumpHost(
      tester,
      const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: WelcomeBackCard(name: 'Jagadishwar Reddy'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back, Jagadishwar'), findsOneWidget);
    expect(find.textContaining('streak'), findsNothing);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Welcome back'), findsNothing);
  });

  testWidgets('welcome-back card is absent for a daily user', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpHost(tester, const WelcomeBackCard(name: 'Asha'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Welcome back'), findsNothing);
  });
}
