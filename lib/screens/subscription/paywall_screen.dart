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
import '../../core/utils/entitlement_gate.dart';
import '../../services/notification_service.dart';
import '../../services/plan_limits.dart';
import '../../widgets/ui/ui.dart';

/// The Proteinix Pro paywall — one plan, billed monthly or yearly through
/// Google Play. Shown when a Free user reaches a Pro feature or runs out of
/// the day's free photo scans (see requireEntitlement), or taps Upgrade.
///
/// Everything about money on this screen comes from the store product: the
/// price, and whether a free trial applies to *this* account. Nothing is
/// charged, promised or hidden that Play itself would not show at checkout —
/// the price after a trial is on screen before the button is.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.feature});

  /// What the user was trying to do when they landed here, so the headline
  /// can say why they are looking at a paywall. Null from the Upgrade button.
  final ProFeature? feature;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  Package? _selected;
  bool _purchasing = false;
  bool _restoring = false;
  String? _error;

  static const _perks = [
    (Icons.camera_alt_rounded, 'Unlimited photo scans'),
    (Icons.mic_rounded, 'Log meals hands-free by voice'),
    (
      Icons.auto_awesome_rounded,
      'Personal AI coach that knows your daily numbers'
    ),
  ];

  String get _headline => switch (widget.feature) {
        ProFeature.photoScan => "You've used today's free scans",
        ProFeature.voiceLog => 'Voice logging is a Pro feature',
        ProFeature.textLog => 'AI logging is a Pro feature',
        ProFeature.coach => 'The AI Coach is a Pro feature',
        null => 'Go Pro',
      };

  String get _subhead => switch (widget.feature) {
        ProFeature.photoScan =>
          'Free includes ${PlanLimits.freeScansPerDay} photo scans a day. '
              'Search and barcode logging stay free and unlimited.',
        _ => 'Search, barcode logging and your dashboard stay free. '
            'Free also includes ${PlanLimits.freeScansPerDay} photo scans '
            'a day.',
      };

  /// What the main button says for [p]: the trial if Play will grant one to
  /// this account, the price otherwise.
  String _cta(Package p) {
    final days = SubscriptionService.freeTrialDays(p);
    if (days > 0) return 'Start $days-day free trial';
    return 'Subscribe — ${_priceWithPeriod(p)}';
  }

  String _priceWithPeriod(Package p) {
    final price = p.storeProduct.priceString;
    return switch (p.packageType) {
      PackageType.annual => '$price / year',
      PackageType.monthly => '$price / month',
      PackageType.weekly => '$price / week',
      _ => price,
    };
  }

  /// The terms, in full, directly under the button — what is charged, when,
  /// and how to stop it. Shown for whichever plan is selected.
  String _terms(Package p) {
    final days = SubscriptionService.freeTrialDays(p);
    final price = _priceWithPeriod(p);
    if (days > 0) {
      return 'Free for $days days, then $price, charged to your Google Play '
          'account. We will remind you '
          '${NotificationService.trialReminderLead.inDays} days before the '
          'trial ends. Cancel any time in one tap from Profile → '
          'Subscription and you will not be charged.';
    }
    return '$price, charged to your Google Play account and renewed '
        'automatically. Cancel any time in one tap from Profile → '
        'Subscription.';
  }

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
    final trialDays = SubscriptionService.freeTrialDays(p);
    if (trialDays > 0) {
      return '$trialDays days free, then ${_priceWithPeriod(p)}';
    }
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
      // Booked before anything else can go wrong: the paywall promised a
      // reminder ahead of the first charge, so a trial must never start
      // without one.
      final trialEnd = SubscriptionService.trialEnd(info);
      if (trialEnd != null) {
        await NotificationService.scheduleTrialEndingReminder(
          trialEnd: trialEnd,
          priceLabel: _priceWithPeriod(pkg),
        );
      }
      if (!mounted) return;
      ref.invalidate(isPremiumProvider);
      if (entitled) {
        context.pop(true);
        return;
      }
      setState(() => _error =
          "Purchase went through but Pro didn't unlock — try Restore Purchases, or contact support.");
    } on PlatformException catch (e) {
      final cancelled = PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError;
      if (!cancelled && mounted) {
        setState(() => _error = 'Purchase failed. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Purchase failed. Please try again.');
      }
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
      appBar: const TerraAppBar(title: '${AppStrings.appName} Pro'),
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
                // Naming the reason they are here. Someone who has just run
                // out of free scans is a different person from someone
                // browsing plans from Settings, and a headline that ignores
                // which one they are reads as a generic sales pitch.
                Text(
                  _headline,
                  textAlign: TextAlign.center,
                  style: AppText.headlineLg(),
                ),
                const SizedBox(height: 6),
                Text(
                  _subhead,
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
                  label: _purchasing
                      ? 'Processing…'
                      : _selected == null
                          ? 'Subscribe'
                          : _cta(_selected!),
                  loading: _purchasing,
                  onPressed: (busy || _selected == null) ? null : _purchase,
                ),
                if (_selected != null) ...[
                  const SizedBox(height: 10),
                  // The price after the trial sits right under the button
                  // that starts it, never behind a link or a second screen.
                  Text(
                    _terms(_selected!),
                    textAlign: TextAlign.center,
                    style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                  ),
                ],
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
      title: 'Pro unavailable',
      message:
          "Couldn't load subscription plans. Check your connection and try again.",
      accent: AppColors.error,
    );
  }
}
