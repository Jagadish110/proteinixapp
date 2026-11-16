import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../providers/subscription_provider.dart';
import '../services/ad_service.dart';

/// The banner at the bottom of the home dashboard — the only ad in the app.
///
/// Takes up no space at all unless an ad has actually loaded: Pro users,
/// builds without an ad unit, offline launches and no-fill responses all
/// render nothing, so the dashboard never shows an empty grey box.
class HomeBannerAd extends ConsumerStatefulWidget {
  const HomeBannerAd({super.key});

  @override
  ConsumerState<HomeBannerAd> createState() => _HomeBannerAdState();
}

class _HomeBannerAdState extends ConsumerState<HomeBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_requested || !AdService.isConfigured) return;
    _requested = true;
    try {
      await AdService.ensureInitialized();
      if (!mounted) return;
      final ad = BannerAd(
        adUnitId: AdService.bannerUnitId,
        size: AdSize.banner,
        request: AdService.request(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            if (mounted) {
              setState(() {
                _ad = null;
                _loaded = false;
              });
            }
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      // An ad that will not load is never worth an error on the dashboard.
    }
  }

  void _remove() {
    final ad = _ad;
    if (ad == null) return;
    _ad = null;
    _loaded = false;
    unawaited(ad.dispose());
  }

  @override
  Widget build(BuildContext context) {
    if (!AdService.isConfigured) return const SizedBox.shrink();

    // Unknown (still loading, or the lookup failed) is treated as "do not
    // show": briefly showing an ad to a paying subscriber is the worse error.
    final isPro = ref.watch(isPremiumProvider).value;
    if (isPro != false) {
      // Covers the moment a Free user subscribes with the dashboard open.
      _remove();
      return const SizedBox.shrink();
    }

    if (!_requested) unawaited(_load());

    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
