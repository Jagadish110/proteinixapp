import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../services/subscription_service.dart';
import '../../widgets/ui/ui.dart';

/// Profile → Subscription: shows the account's current plan and renewal
/// status if premium, or pricing + an upsell into the paywall if not.
/// Pricing shown here (₹199/mo, ₹1,499/yr) must match whatever products are
/// actually created in Google Play Console — this screen only displays
/// them, it can't set them.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  CustomerInfo? _info;
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
      if (!mounted) return;
      setState(() {
        _info = info;
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
                    PillButton(
                      label: 'Manage subscription',
                      tone: PillTone.outline,
                      icon: Icons.open_in_new_rounded,
                      glow: false,
                      onPressed: () => _openManagement(_info!.managementURL!),
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
    final planLabel = e.productIdentifier.toLowerCase().contains('annual')
        ? 'Annual'
        : 'Monthly';

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
                Text('Premium — $planLabel', style: AppText.headlineMd()),
                const SizedBox(height: 2),
                Text(
                  expiry == null
                      ? 'Active'
                      : e.willRenew
                          ? 'Renews ${_fmt(expiry)}'
                          : 'Ends ${_fmt(expiry)} — not renewing',
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
                      'AI food scanning, voice logging and AI Coach are '
                      'Premium features.',
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
          _priceRow('Monthly', '₹199 / mo'),
          const SizedBox(height: 8),
          _priceRow('Annual', '₹1,499 / yr — save 37%'),
          const SizedBox(height: AppSpacing.md),
          PillButton(
            label: 'Upgrade to Premium',
            icon: Icons.auto_awesome_rounded,
            onPressed: _upgrade,
          ),
        ],
      ),
    );
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
