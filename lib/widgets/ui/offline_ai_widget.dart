import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../services/connectivity_service.dart';
import 'pill_button.dart';

/// Placeholder for the features that genuinely can't work offline — anything
/// that calls Gemini.
///
/// Everything else in the app is local-first, so this should only ever appear
/// on the AI Coach and the food scanner.
class OfflineAIWidget extends StatefulWidget {
  const OfflineAIWidget({super.key, required this.featureName, this.onRetry});

  /// e.g. "AI Food Scanner".
  final String featureName;

  /// Called after a retry that found a connection.
  final VoidCallback? onRetry;

  @override
  State<OfflineAIWidget> createState() => _OfflineAIWidgetState();
}

class _OfflineAIWidgetState extends State<OfflineAIWidget> {
  bool _checking = false;

  Future<void> _retry() async {
    setState(() => _checking = true);
    final online = await ConnectivityService.checkConnection();
    if (!mounted) return;
    setState(() => _checking = false);
    if (online) {
      widget.onRetry?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still offline.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 56, color: AppColors.onSurfaceVariant),
            const SizedBox(height: AppSpacing.gutter),
            Text(
              '${widget.featureName} needs\nan internet connection',
              textAlign: TextAlign.center,
              style: AppText.headlineMd(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your meals, water and progress all keep working offline — '
              'only the AI features need to reach the server.',
              textAlign: TextAlign.center,
              style: AppText.bodySm(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            PillButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              loading: _checking,
              onPressed: _checking ? null : _retry,
            ),
          ],
        ),
      ),
    );
  }
}
