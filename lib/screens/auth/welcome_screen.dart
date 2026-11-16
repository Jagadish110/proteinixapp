import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../services/guest_mode.dart';
import '../../widgets/ui/ui.dart';

/// First-run landing screen: brand mark over a full-bleed food photograph,
/// with a glassmorphic action container pinned to the bottom.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The photo is 2:3 but phones are nearer 9:20, so cover crops ~500px
          // of width. Biasing right spends most of that crop on the empty left
          // half of the shot and keeps the bowls' edges intact; a centred crop
          // slices the corn and tempeh off the right-hand bowls.
          Image.asset(
            'assets/images/welcome_bowls.jpg',
            fit: BoxFit.cover,
            alignment: const Alignment(0.35, 0),
            // A decode failure would otherwise leave white text on white.
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: AppColors.background),
          ),

          // Scrim. Light through the middle so the food still reads, weighted
          // at top and bottom where the wordmark and the glass panel sit.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x8C000000),
                  Color(0x4D000000),
                  Color(0xC4000000),
                  Color(0xEB000000),
                ],
                stops: [0, 0.35, 0.75, 1],
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 3),
                  Text(AppStrings.appName,
                      style: AppText.display(color: AppColors.primary)),
                  const SizedBox(height: 8),
                  Text(AppStrings.tagline.toUpperCase(),
                      style: AppText.labelCaps(size: 12)),
                  const Spacer(flex: 2),
                  Text(
                    AppStrings.welcomeHeadline,
                    style: AppText.headlineLg()
                        .copyWith(fontSize: 30, height: 1.25),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      AppStrings.welcomeBody,
                      style: AppText.body(color: AppColors.onSurfaceVariant)
                          .copyWith(height: 1.6),
                    ),
                  ),
                  const Spacer(flex: 3),
                  _GlassActions(
                    onGetStarted: () => context.go('/signup'),
                    onSignIn: () => context.go('/login'),
                    onExplore: () async {
                      await GuestMode.enable();
                      if (context.mounted) context.go('/home');
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassActions extends StatelessWidget {
  const _GlassActions({
    required this.onGetStarted,
    required this.onSignIn,
    required this.onExplore,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.cardR,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          // Full width so the call to action lands on the screen's centre line
          // rather than sitting off to one side.
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: AppRadius.cardR,
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PillButton(
                label: AppStrings.getStarted,
                tone: PillTone.hot,
                trailingIcon: Icons.arrow_forward_rounded,
                onPressed: onGetStarted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account?',
                      style: AppText.body(color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onSignIn,
                    behavior: HitTestBehavior.opaque,
                    child: Text(AppStrings.signIn,
                        style: AppText.bodyBold(color: AppColors.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onExplore,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Explore without an account',
                    style: AppText.bodyBold(color: AppColors.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
