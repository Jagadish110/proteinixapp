import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../services/notification_service.dart';
import '../../services/plan_limits.dart';
import '../../services/subscription_service.dart';
import '../../widgets/ui/ui.dart';

/// Profile → Subscription: the account's current plan and renewal status if
/// on Pro, with a one-tap cancel, or what Free includes plus an upsell into
/// the paywall if not.
///
/// Prices are read from the store offering, so they always match what Play
/// will charge. The ₹49 / ₹399 fallbacks are only shown when the offering
/// cannot be loaded (offline, or the products not yet live).
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  CustomerInfo? _info;
  Offering? _offering;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final info = await Purchases.getCustomerInfo();
      final offering = await SubscriptionService.instance.getOffering();
      // A trial cancelled in Play, or one that has converted, no longer needs
      // its "ends soon" reminder.
      final e = info.entitlements.active[SubscriptionService.entitlementId];
      if (e == null || e.periodType != PeriodType.trial || !e.willRenew) {
        await NotificationService.cancelTrialEndingReminder();
      }
      if (!mounted) return;
      setState(() {
        _info = info;
        _offering = offering;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upgrade() async {
    await context.push('/paywall');
    _load();
  }

  Future<void> _openManagement(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final entitlement =
        _info?.entitlements.active[SubscriptionService.entitlementId];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TerraAppBar(title: 'Subscription'),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                    AppSpacing.md, AppSpacing.page, AppSpacing.lg),
                children: [
                  entitlement != null ? _activeCard(entitlement) : _freeCard(),
                  if (entitlement != null && _info?.managementURL != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    // One tap from here to Google Play's own cancel screen for
                    // this subscription. Play is the only place a Play
                    // subscription can be cancelled, so the honest version of
                    // "one-tap cancel" is a button that goes straight there.
                    PillButton(
                      label: entitlement.willRenew
                          ? 'Cancel subscription'
                          : 'Manage in Google Play',
                      tone: PillTone.outline,
                      icon: Icons.open_in_new_rounded,
                      glow: false,
                      onPressed: () => _openManagement(_info!.managementURL!),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entitlement.willRenew
                          ? 'Opens Google Play. You keep Pro until the end of '
                              'the period you have already paid for.'
                          : 'Renewal is off. You keep Pro until it ends.',
                      textAlign: TextAlign.center,
                      style:
                          AppText.bodySm(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: TextButton(
                      onPressed: _load,
                      child: Text('Refresh status',
                          style: AppText.bodySm(
                              color: AppColors.onSurfaceVariant)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _activeCard(EntitlementInfo e) {
    final expiry =
        e.expirationDate != null ? DateTime.tryParse(e.expirationDate!) : null;
    final id = e.productIdentifier.toLowerCase();
    final planLabel =
        (id.contains('annual') || id.contains('year')) ? 'Yearly' : 'Monthly';
    final onTrial = e.periodType == PeriodType.trial;

    return TerraCard(
      child: Row(
        children: [
          const IconBubble(
            icon: Icons.workspace_premium_rounded,
            color: AppColors.primary,
            size: 44,
            tinted: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(onTrial ? 'Pro — free trial' : 'Pro — $planLabel',
                    style: AppText.headlineMd()),
                const SizedBox(height: 2),
                Text(
                  expiry == null
                      ? 'Active'
                      : !e.willRenew
                          ? 'Ends ${_fmt(expiry)} — not renewing'
                          : onTrial
                              ? 'Trial ends ${_fmt(expiry)}, then renews '
                                  '${planLabel.toLowerCase()}'
                              : 'Renews ${_fmt(expiry)}',
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _freeCard() {
    return TerraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBubble(
                icon: Icons.lock_outline_rounded,
                color: AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Free plan', style: AppText.headlineMd()),
                    const SizedBox(height: 2),
                    Text(
                      '${PlanLimits.freeScansPerDay} photo scans a day. '
                      'Search, barcode logging and your dashboard are '
                      'always free.',
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(color: AppColors.outline),
          const SizedBox(height: AppSpacing.sm),
          Text('Pro adds unlimited scans, voice logging, the AI Coach and '
              'no ads.',
              style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: AppSpacing.sm),
          _priceRow('Monthly', _price(_offering?.monthly, '₹49', 'mo')),
          const SizedBox(height: 8),
          _priceRow('Yearly', _price(_offering?.annual, '₹399', 'yr')),
          const SizedBox(height: AppSpacing.md),
          PillButton(
            label: 'Go Pro',
            icon: Icons.auto_awesome_rounded,
            onPressed: _upgrade,
          ),
        ],
      ),
    );
  }

  /// The store's own price for [p], with the trial it carries if any.
  static String _price(Package? p, String fallback, String per) {
    if (p == null) return '$fallback / $per';
    final price = '${p.storeProduct.priceString} / $per';
    final days = SubscriptionService.freeTrialDays(p);
    return days > 0 ? '$price · $days days free' : price;
  }

  Widget _priceRow(String label, String price) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.body()),
        Text(price, style: AppText.bodyBold(color: AppColors.primary)),
      ],
    );
  }
}
