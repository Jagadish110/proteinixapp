import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';

/// One reason someone gets in touch. The subject is what lands in the
/// inbox, so it doubles as the triage label.
typedef _Topic = ({String title, String blurb, IconData icon, String subject});

/// Contact screen: picks a topic, then hands a pre-addressed, pre-filled
/// draft to the phone's mail app.
///
/// Deliberately not a form that posts somewhere. A refund or a locked-out
/// account needs a reply, and a mail thread is a reply channel the user
/// already owns — a fire-and-forget form gives them no record that they
/// asked and no way to follow up.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _topics = <_Topic>[
    (
      title: 'Refund or billing',
      blurb: 'Charges, cancellations and refund requests',
      icon: Icons.receipt_long_outlined,
      subject: 'Refund / billing request',
    ),
    (
      title: "Can't sign in",
      blurb: 'Password resets, Google sign-in, locked accounts',
      icon: Icons.lock_outline_rounded,
      subject: 'Sign-in problem',
    ),
    (
      title: 'Something looks wrong',
      blurb: 'Missing data, wrong numbers, a screen that misbehaves',
      icon: Icons.bug_report_outlined,
      subject: 'Bug report',
    ),
    (
      title: 'Delete my account',
      blurb: 'Ask for your account and data to be removed',
      icon: Icons.person_off_outlined,
      subject: 'Account deletion request',
    ),
    (
      title: 'Something else',
      blurb: 'Feedback, a feature idea, anything not listed above',
      icon: Icons.chat_bubble_outline_rounded,
      subject: 'Support request',
    ),
  ];

  /// Facts worth having before the first reply, appended to every draft.
  ///
  /// The account id is the useful one — it's what identifies the rows to look
  /// at server-side, and asking for it over email is a round trip that
  /// usually ends in "where do I find that?".
  static String _diagnosticFooter() {
    final uid = SupabaseService.currentUserId;
    return '\n\n---\n'
        'Please keep the details below — they help us find your account.\n'
        'App: ${AppStrings.appFullName} ${AppStrings.appVersion}\n'
        'Account: ${uid ?? 'not signed in'}\n';
  }

  Future<void> _compose(BuildContext context, _Topic topic) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppStrings.supportEmail,
      queryParameters: {
        'subject': '[${AppStrings.appName}] ${topic.subject}',
        'body': 'Hi,\n\n${_diagnosticFooter()}',
      },
    );

    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;

    // No mail app configured, which is common enough on a fresh device that
    // it can't just fail silently — the address is the whole point of the
    // screen, so hand it over in a form they can paste elsewhere.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text('Email us', style: AppText.headlineMd()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "We couldn't open a mail app. You can reach us at:",
              style: AppText.body(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(AppStrings.supportEmail,
                style: AppText.bodyBold(color: AppColors.primary)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(
                  const ClipboardData(text: AppStrings.supportEmail));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Address copied'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Copy address'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TerraAppBar(title: 'Support'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.lg),
        children: [
          Text('How can we help?', style: AppText.headlineLg()),
          const SizedBox(height: 6),
          Text(
            'Pick what this is about and we\'ll start an email for you. '
            'We read every message.',
            style: AppText.body(color: AppColors.onSurfaceVariant)
                .copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final topic in _topics) ...[
            TerraListRow(
              title: topic.title,
              subtitle: topic.blurb,
              icon: topic.icon,
              iconColor: AppColors.primary,
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceVariant),
              onTap: () => _compose(context, topic),
            ),
            const SizedBox(height: 12),
          ],
          // The address is deliberately not printed here. Picking a topic
          // hands it to the mail app already filled in, so showing it as
          // plain text adds nothing but a scrapeable inbox on a screen every
          // user can open. The no-mail-app dialog is the one place it still
          // appears, because there it is the only way to make contact.
        ],
      ),
    );
  }
}
