import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/subscription_service.dart';
import '../../services/trial_service.dart';

/// Call this immediately before any Gemini-backed action — photo scan, text or
/// voice food logging, AI Coach message.
///
/// Returns true when the user may proceed: either they hold the "premium"
/// entitlement, or they are inside the three-day free trial. Otherwise it shows
/// the paywall and returns true only if they subscribe there and then, so the
/// original tap completes instead of making them repeat it.
///
/// Order matters. The trial is checked *first* and locally, because it answers
/// for every user in their first three days without a network round trip to
/// RevenueCat — and it must never be possible for a slow or failed entitlement
/// lookup to paywall someone whose trial is plainly still running.
/// Master switch for premium enforcement.
///
/// False while the app is in testing, so every AI feature is open to everyone
/// and nobody is asked to pay for something still being shaken out. The gate
/// stays wired into all four call sites — flipping this to true is the whole
/// job of turning premium on, and there is nothing else to remember.
///
/// Requires the Play Console products and the RevenueCat `premium` entitlement
/// to exist first; without them the paywall can only show its unavailable
/// state, which would lock the AI features behind a door with no handle.
const bool kEnforcePremium = false;

Future<bool> requireEntitlement(BuildContext context, WidgetRef ref) async {
  if (!kEnforcePremium) return true;
  if (TrialService.state().active) return true;

  final entitled = await SubscriptionService.instance.isEntitled();
  if (entitled) return true;

  if (!context.mounted) return false;
  final purchased = await context.push<bool>('/paywall');
  return purchased ?? false;
}
