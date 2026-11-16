import 'package:flutter/material.dart';

import '../../services/error_reporter.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_typography.dart';
import '../../widgets/ui/ui.dart';

/// Reports a failure and tells the user something a person would say.
///
/// The raw exception never reaches the screen. `PostgrestException(message:
/// duplicate key value violates unique constraint …)` tells the user nothing
/// they can act on, looks broken, and leaks table names — while the detail
/// that *is* useful goes to `error_logs` and Diagnostics instead, where it
/// can actually be read.
///
/// [context] is the failed action, e.g. `save_profile`, and is what the
/// server row is triaged by.
Future<void> showTechnicalIssue(
  BuildContext context, {
  required String action,
  required String reportContext,
  required Object error,
  StackTrace? stack,
  VoidCallback? onRetry,
}) async {
  await ErrorReporter.report(reportContext, error, stack);
  if (!context.mounted) return;

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
                  icon: Icons.cloud_off_rounded,
                  color: AppColors.tertiary,
                  tinted: true,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child:
                      Text('Something went wrong', style: AppText.headlineMd()),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "We couldn't $action just now. Our team has been notified "
              'automatically — please try again in a moment.',
              style: AppText.body(color: AppColors.onSurfaceVariant)
                  .copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            if (onRetry != null) ...[
              PillButton(
                label: 'Try again',
                onPressed: () {
                  Navigator.pop(ctx);
                  onRetry();
                },
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            PillButton(
              label: onRetry == null ? 'OK' : 'Not now',
              tone: onRetry == null ? PillTone.primary : PillTone.neutral,
              glow: onRetry == null,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The same idea for cases too small to interrupt with a sheet — a failed
/// background save, a list that wouldn't refresh.
void showTechnicalIssueSnack(
  BuildContext context, {
  required String action,
  required String reportContext,
  required Object error,
  StackTrace? stack,
}) {
  ErrorReporter.report(reportContext, error, stack);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
        content: Text("Couldn't $action — please try again."),
      ),
    );
}
