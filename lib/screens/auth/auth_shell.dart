import 'package:flutter/material.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/ui/ui.dart';

/// Shared chrome for sign-in / sign-up: back + brand row, serif-weight headline,
/// then a single elevated surface holding the form.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    this.footer,
    this.onBack,
    required this.children,
  });

  final String title;
  final String subtitle;
  final Widget? footer;
  final VoidCallback? onBack;
  final List<Widget> children;

  /// Most screens using this shell are reached via `context.go(...)`, which
  /// (unlike `push`) doesn't leave anything on the Navigator stack for the
  /// system back button/gesture to pop — only the on-screen arrow, wired to
  /// [onBack], actually went anywhere. Wrapping in PopScope routes system
  /// back through the exact same callback so both behave identically.
  void _handleBack(BuildContext context) =>
      (onBack ?? () => Navigator.maybePop(context))();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        body: DismissKeyboard(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => _handleBack(context),
                        icon: const Icon(Icons.arrow_back_rounded,
                            size: 20, color: AppColors.primary),
                        label: Text('Back',
                            style: AppText.bodyBold(color: AppColors.primary)),
                      ),
                      const Spacer(),
                      Text(AppStrings.appName,
                          style: AppText.headlineLg(color: AppColors.primary)),
                      const Spacer(),
                      const SizedBox(width: 80),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    // No manual viewInsets padding here: `resizeToAvoidBottomInset`
                    // already shrinks the body by the keyboard height, so adding
                    // the inset again double-counted it *and* made this whole
                    // subtree rebuild on every frame of the keyboard animation —
                    // which is what dropped focus mid-open.
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AppText.display()
                            .copyWith(fontSize: 34, height: 1.2),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: AppText.body(color: AppColors.onSurfaceVariant)
                            .copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: AppRadius.cardR,
                          border: Border.all(color: AppColors.outline),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        ),
                      ),
                      if (footer != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, this.label = 'OR'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.outline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(label, style: AppText.labelCaps(size: 12)),
        ),
        const Expanded(child: Divider(color: AppColors.outline)),
      ],
    );
  }
}

class AuthFooter extends StatelessWidget {
  const AuthFooter({
    super.key,
    required this.question,
    required this.action,
    required this.onTap,
  });

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(question, style: AppText.body(color: AppColors.onSurfaceVariant)),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child:
              Text(action, style: AppText.bodyBold(color: AppColors.primary)),
        ),
      ],
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer.withValues(alpha: 0.25),
        borderRadius: AppRadius.lgR,
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: AppText.bodySm(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}
