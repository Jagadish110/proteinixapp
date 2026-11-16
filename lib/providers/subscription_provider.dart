import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/subscription_service.dart';

/// Whether the signed-in user currently holds the "premium" entitlement.
/// Invalidate this after a purchase/restore completes so gated screens see
/// the change immediately.
final isPremiumProvider = FutureProvider<bool>((ref) {
  return SubscriptionService.instance.isEntitled();
});

/// The single subscription offering (monthly + annual packages) configured
/// in the RevenueCat dashboard.
final subscriptionOfferingProvider = FutureProvider<Offering?>((ref) {
  return SubscriptionService.instance.getOffering();
});
