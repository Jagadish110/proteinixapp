import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proteinix/core/theme/app_theme.dart';
import 'package:proteinix/core/utils/entitlement_gate.dart';
import 'package:proteinix/providers/subscription_provider.dart';
import 'package:proteinix/screens/subscription/paywall_screen.dart';
import 'package:proteinix/services/subscription_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// The paywall is the one screen where wrong copy is a billing problem, not a
/// cosmetic one. These pin what it says against store products shaped the way
/// Play returns them: ₹49 monthly with no trial, ₹399 yearly with 7 days free.

const _ctx = PresentedOfferingContext('default', null, null);

PricingPhase _phase(Period period, String formatted, int micros,
        {OfferPaymentMode? mode}) =>
    PricingPhase(
      period,
      RecurrenceMode.infiniteRecurring,
      null,
      Price(formatted, micros, 'INR'),
      mode,
    );

Package monthly() => const Package(
      r'$rc_monthly',
      PackageType.monthly,
      StoreProduct(
          'pro_monthly', 'Proteinix Pro', 'Pro (Monthly)', 49, '₹49.00', 'INR'),
      _ctx,
    );

Package yearly({bool trial = true}) {
  const year = Period(PeriodUnit.year, 1, 'P1Y');
  final full = _phase(year, '₹399.00', 399000000);
  final free = _phase(const Period(PeriodUnit.day, 7, 'P7D'), 'Free', 0,
      mode: OfferPaymentMode.freeTrial);
  return Package(
    r'$rc_annual',
    PackageType.annual,
    StoreProduct(
      'pro_yearly',
      'Proteinix Pro',
      'Pro (Yearly)',
      399,
      '₹399.00',
      'INR',
      defaultOption: SubscriptionOption(
        'yearly',
        'pro_yearly:yearly',
        'pro_yearly',
        trial ? [free, full] : [full],
        const [],
        !trial,
        year,
        false,
        full,
        trial ? free : null,
        null,
        _ctx,
        null,
      ),
    ),
    _ctx,
  );
}

Offering offering({bool trial = true}) {
  final m = monthly();
  final y = yearly(trial: trial);
  return Offering('default', 'Pro', const {}, [m, y], monthly: m, annual: y);
}

Future<void> pumpPaywall(
  WidgetTester tester, {
  bool trial = true,
  ProFeature? feature,
  double width = 320,
  double textScale = 1.3,
}) async {
  tester.view.physicalSize = Size(width * 3, 760 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      subscriptionOfferingProvider
          .overrideWith((ref) => offering(trial: trial)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: PaywallScreen(feature: feature),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 120,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  test('trial length is read from the store product', () {
    expect(SubscriptionService.freeTrialDays(yearly()), 7);
    expect(SubscriptionService.freeTrialDays(yearly(trial: false)), 0);
    expect(SubscriptionService.freeTrialDays(monthly()), 0);
  });

  testWidgets('yearly is preselected and shows the trial with its price',
      (tester) async {
    await pumpPaywall(tester);

    // The plan card, the button and the terms all agree.
    await scrollTo(tester, find.text('Start 7-day free trial'));
    expect(find.text('7 days free, then ₹399.00 / year'), findsOneWidget);

    final terms = find.textContaining('Free for 7 days, then ₹399.00 / year');
    await scrollTo(tester, terms);
    final text = tester.widget<Text>(terms).data!;
    expect(text, contains('remind you 2 days before'));
    expect(text, contains('Cancel any time in one tap'));
  });

  testWidgets('monthly has no trial and says what it charges', (tester) async {
    await pumpPaywall(tester);

    await scrollTo(tester, find.text('Monthly'));
    expect(find.text('₹49.00 / month'), findsOneWidget);
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Subscribe — ₹49.00 / month'));
    expect(find.text('Start 7-day free trial'), findsNothing);
    expect(find.textContaining('Free for'), findsNothing);
  });

  testWidgets('an account Play gives no trial to is not promised one',
      (tester) async {
    await pumpPaywall(tester, trial: false);

    await scrollTo(tester, find.text('Subscribe — ₹399.00 / year'));
    expect(find.textContaining('free trial'), findsNothing);
    expect(find.textContaining('days free'), findsNothing);
  });

  testWidgets('says why the user is here', (tester) async {
    await pumpPaywall(tester, feature: ProFeature.photoScan);
    expect(find.text("You've used today's free scans"), findsOneWidget);
    expect(find.textContaining('3 photo scans a day'), findsOneWidget);
  });
}
