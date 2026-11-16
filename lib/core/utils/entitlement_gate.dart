import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/plan_limits.dart';
import '../../services/subscription_service.dart';
import '../constants/api_keys.dart';

/// The AI features, by how each plan treats them.
///
/// | Feature     | Free        | Pro       |
/// |-------------|-------------|-----------|
/// | [photoScan] | 3 a day     | unlimited |
/// | [textLog]   | —           | included  |
/// | [voiceLog]  | —           | included  |
/// | [coach]     | —           | included  |
///
/// Search, barcode scanning, saved meals and the dashboard are not listed
/// because they are never gated: they are free and unlimited on every plan.
enum ProFeature { photoScan, textLog, voiceLog, coach }

/// Master switch for the Free / Pro split, set by `ENFORCE_PREMIUM=true` in
/// `.env` (see [ApiKeys.enforcePremium]).
///
/// False while the app is in testing, so every AI feature is open to everyone
/// and nobody is asked to pay for something still being shaken out. The gate
/// stays wired into every call site — turning this on is the whole job of
/// turning Pro on, and there is nothing else to remember.
///
/// Requires the Play Console products and the RevenueCat `premium` entitlement
/// to exist first; without them the paywall can only show its unavailable
/// state.
bool get kEnforcePremium => ApiKeys.enforcePremium;

/// Call this immediately before any Gemini-backed action.
///
/// Returns true when the user may proceed: they hold the `premium`
/// entitlement, or [feature] is a photo scan and they still have one of
/// today's free scans left. Otherwise it shows the paywall and returns true
/// only if they subscribe there and then, so the original tap completes
/// instead of making them repeat it.
///
/// There is no account-age free trial any more. The only trial is the 7-day
/// one Google Play attaches to the yearly plan, which is a real subscription
/// state and so is already covered by the entitlement check.
Future<bool> requireEntitlement(
  BuildContext context,
  WidgetRef ref, {
  required ProFeature feature,
}) async {
  if (!kEnforcePremium) return true;

  if (await SubscriptionService.instance.isEntitled()) return true;

  if (feature == ProFeature.photoScan &&
      await PlanLimits.freeScansLeft() > 0) {
    return true;
  }

  if (!context.mounted) return false;
  final purchased = await context.push<bool>('/paywall', extra: feature);
  return purchased ?? false;
}
