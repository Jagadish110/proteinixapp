import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_typography.dart';

/// Guards an action that would create or change the user's own data.
///
/// Returns true when there is a signed-in user and the caller should carry on.
/// Otherwise it explains why the action needs an account and returns false —
/// so every call site reads as `if (!await requireAccount(context)) return;`.
///
/// [action] completes the sentence "… to <action>", e.g. "log this meal".
Future<bool> requireAccount(BuildContext context, {String? action}) async {
  if (SupabaseService.isLoggedIn) return true;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.page,
        right: AppSpacing.page,
        bottom: MediaQuery.of(ctx).padding.bottom + AppSpacing.md,
      ),
      child: TerraCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBubble(
                  icon: Icons.lock_open_rounded,
                  color: AppColors.primary,
                  tinted: true,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Create an account to continue',
                      style: AppText.headlineMd()),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              action == null
                  ? 'Your meals, water and progress are saved to your account so '
                      'they follow you across devices.'
                  : "You'll need an account to $action. It only takes a moment, "
                      'and your progress is saved across devices.',
              style: AppText.body(color: AppColors.onSurfaceVariant)
                  .copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            PillButton(
              label: 'Create account',
              trailingIcon: Icons.arrow_forward_rounded,
              onPressed: () {
                Navigator.pop(ctx);
                ctx.go('/signup');
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            PillButton(
              label: 'I already have an account',
              tone: PillTone.neutral,
              glow: false,
              onPressed: () {
                Navigator.pop(ctx);
                ctx.go('/login');
              },
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Keep looking around',
                    style: AppText.bodyBold(color: AppColors.onSurfaceVariant)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return false;
}
