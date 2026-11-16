import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme/app_colors.dart';
import 'notification_service.dart';

/// Why a reminder toggle couldn't be turned on.
enum NotificationBlocker {
  /// Nothing is blocking — reminders will be delivered.
  none,

  /// Android 13+ POST_NOTIFICATIONS was declined this time.
  notificationsDenied,

  /// POST_NOTIFICATIONS was declined with "don't ask again"; only the system
  /// settings screen can undo it.
  notificationsPermanentlyDenied,
}

/// Requests the one permission a reminder needs.
///
/// Deliberately only POST_NOTIFICATIONS. Exact-alarm access and a
/// battery-optimisation exemption would both make delivery more punctual, and
/// both were dropped on purpose: each is *special access* that can only be
/// granted from a system settings screen, so each turns "enable reminders" into
/// a trip out of the app that most people abandon. Switching notifications on
/// is the whole setup.
///
/// The cost is real and is not hidden: without them Android batches reminders
/// into Doze maintenance windows, so they can arrive late and several at once.
class NotificationPermissionService {
  const NotificationPermissionService._();

  /// Requests notification permission and reports what (if anything) still
  /// blocks delivery.
  static Future<NotificationBlocker> request(BuildContext context) async {
    if (!Platform.isAndroid) return NotificationBlocker.none;

    // The only gate. Without it nothing is ever posted, however perfectly the
    // alarm fires.
    if (!await NotificationService.areNotificationsEnabled()) {
      final granted = await NotificationService.requestNotificationPermission();
      if (!granted) {
        if (await NotificationService
            .isNotificationPermissionPermanentlyDenied()) {
          if (context.mounted) {
            await _showSettingsDialog(
              context,
              title: 'Notifications are blocked',
              message:
                  'Proteinix can\'t send reminders until notifications are '
                  'turned on for the app. Open Settings → Notifications and '
                  'allow them.',
            );
          }
          return NotificationBlocker.notificationsPermanentlyDenied;
        }
        return NotificationBlocker.notificationsDenied;
      }
    }

    return NotificationBlocker.none;
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  static Future<void> _showSettingsDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.onPrimaryContainer,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
