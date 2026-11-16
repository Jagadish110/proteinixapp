import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/subscription_provider.dart';
import '../../services/subscription_service.dart';
import '../../services/trial_service.dart';
import '../../widgets/ui/ui.dart';

/// Single-plan paywall — one "premium" entitlement, monthly or annual
/// billing. Shown whenever a free user hits a Gemini-backed feature
/// (see requireEntitlement) or taps a manual upgrade entry point.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Package? _selected;
  // Read once per screen: it is derived from a cached date, and re-reading it
  // mid-build would let the copy change under the user as midnight passes.
  final TrialState _trial = TrialService.state();
  bool _purchasing = false;
  bool _restoring = false;
  String? _error;

  static const _perks = [
    (Icons.camera_alt_rounded, 'Snap a plate — instant calories & macros'),
    (Icons.mic_rounded, 'Log meals hands-free by voice'),
    (
      Icons.auto_awesome_rounded,
      'Personal AI coach that knows your daily numbers'
    ),
  ];

  String _cycleLabel(Package p) {
    switch (p.packageType) {
      case PackageType.monthly:
        return 'Monthly';
      case PackageType.annual:
        return 'Annual';
      case PackageType.weekly:
        return 'Weekly';
      case PackageType.lifetime:
        return 'Lifetime';
      default:
        return p.storeProduct.title;
    }
  }

  String _description(Package p, Offering offering) {
    final price = p.storeProduct.priceString;
    if (p.packageType == PackageType.annual) {
      final monthly = offering.monthly;
      if (monthly != null && monthly.storeProduct.price > 0) {
        final equivMonthly = p.storeProduct.price / 12;
        final savePct = (1 - (equivMonthly / monthly.storeProduct.price)) * 100;
        if (savePct > 1) {
          return '$price / year — save ${savePct.round()}% vs monthly';
        }
      }
      return '$price / year';
    }
    if (p.packageType == PackageType.monthly) return '$price / month';
    return price;
  }

  void _selectDefault(Offering offering) {
    if (_selected != null) return;
    _selected = offering.annual ??
        (offering.availablePackages.isNotEmpty
            ? offering.availablePackages.first
            : null);
  }

  Future<void> _purchase() async {
    final pkg = _selected;
    if (pkg == null || _purchasing) return;
    setState(() {
      _purchasing = true;
      _error = null;
    });
    try {
      final info = await SubscriptionService.instance.purchase(pkg);
      final entitled = info.entitlements.active
          .containsKey(SubscriptionService.entitlementId);
      if (!mounted) return;
      ref.invalidate(isPremiumProvider);
      if (entitled) {
        context.pop(true);
        return;
      }
      setState(() => _error =
          "Purchase went through but premium didn't unlock — try Restore Purchases, or contact support.");
    } on PlatformException catch (e) {
      final cancelled = PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError;
      if (!cancelled && mounted) {
        setState(() => _error = 'Purchase failed. Please try again.');
      }
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Purchase failed. Please try again.');
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      final info = await SubscriptionService.instance.restore();
      final entitled = info.entitlements.active
          .containsKey(SubscriptionService.entitlementId);
      if (!mounted) return;
      ref.invalidate(isPremiumProvider);
      if (entitled) {
        context.pop(true);
        return;
      }
      setState(() => _error = 'No active subscription found for this account.');
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not restore purchases. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offeringAsync = ref.watch(subscriptionOfferingProvider);
    final busy = _purchasing || _restoring;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TerraAppBar(title: '${AppStrings.appName} Premium'),
      body: SafeArea(
        child: offeringAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (_, __) => _unavailable(),
          data: (offering) {
            if (offering == null || offering.availablePackages.isEmpty) {
              return _unavailable();
            }
            _selectDefault(offering);

            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md,
                  AppSpacing.page, AppSpacing.lg),
              children: [
                const Center(
                  child: IconBubble(
                    icon: Icons.auto_awesome_rounded,
                    color: AppColors.primary,
                    size: 72,
                    tinted: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // Naming the reason they are here. Someone whose trial has just
                // run out is a different person from someone browsing plans
                // from Settings, and a headline that ignores which one they are
                // reads as a sales pitch for something they thought they had.
                Text(
                  _trial.expired
                      ? 'Your free trial has ended'
                      : 'Unlock AI-powered logging',
                  textAlign: TextAlign.center,
                  style: AppText.headlineLg(),
                ),
                const SizedBox(height: 6),
                Text(
                  switch (_trial) {
                    TrialState(expired: true) =>
                      'Keep scanning, voice logging and coaching. '
                          'Everything else stays free.',
                    TrialState(active: true, known: true, daysLeft: final d) =>
                      '$d ${d == 1 ? 'day' : 'days'} left on your free trial. '
                          'Subscribe any time.',
                    _ => 'One plan, everything included.',
                  },
                  textAlign: TextAlign.center,
                  style: AppText.body(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.lg),
                ..._perks.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          IconBubble(
                              icon: p.$1,
                              color: AppColors.secondary,
                              size: 40,
                              tinted: true),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(p.$2, style: AppText.body()),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: AppSpacing.sm),
                ...offering.availablePackages.map((pkg) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RadioOptionCard(
                        title: _cycleLabel(pkg),
                        description: _description(pkg, offering),
                        selected: _selected?.identifier == pkg.identifier,
                        onTap: busy
                            ? () {}
                            : () => setState(() => _selected = pkg),
                      ),
                    )),
                const SizedBox(height: AppSpacing.md),
                if (_error != null) ...[
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: AppText.bodySm(color: AppColors.error)),
                  const SizedBox(height: AppSpacing.sm),
                ],
                PillButton(
                  label: _purchasing ? 'Processing…' : 'Subscribe',
                  loading: _purchasing,
                  onPressed: (busy || _selected == null) ? null : _purchase,
                ),
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: TextButton(
                    onPressed: busy ? null : _restore,
                    child: Text(
                      _restoring ? 'Restoring…' : 'Restore purchases',
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _unavailable() {
    return const TerraEmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'Premium unavailable',
      message:
          "Couldn't load subscription plans. Check your connection and try again.",
      accent: AppColors.error,
    );
  }
}
