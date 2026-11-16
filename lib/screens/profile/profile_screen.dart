import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/avatar_picker_sheet.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../services/avatar_service.dart';
import '../../services/error_reporter.dart';
import '../../widgets/ui/ui.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: TerraAppBar(
        title: 'Profile',
        titleColor: AppColors.onSurfaceVariant,
        centerTitle: false,
        actions: [
          // Support, not settings: this used to be a gear that opened
          // Reminders, which is already a row in the list below — so the
          // icon promised settings, duplicated a row, and left no way at all
          // to reach a human about a refund or a locked account.
          CircleIconButton(
            icon: Icons.support_agent_rounded,
            color: AppColors.primary,
            onTap: () => context.push('/support'),
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, s) {
          // Reported, not printed. The raw PostgrestException/SocketException
          // text told the user nothing they could act on and made a dropped
          // connection look like a broken app.
          ErrorReporter.report('profile_load', e, s);
          return const TerraEmptyState(
            icon: Icons.cloud_off_rounded,
            title: "Couldn't load your profile",
            message: 'Check your connection and pull down to try again.',
            accent: AppColors.tertiary,
          );
        },
        data: (p) {
          if (p == null) {
            return TerraEmptyState(
              icon: Icons.person_outline_rounded,
              title: "You're just looking around",
              message: 'Create an account to start logging meals and keep your '
                  'progress across devices.',
              action: SizedBox(
                width: 240,
                child: Column(
                  children: [
                    PillButton(
                      label: 'Create account',
                      trailingIcon: Icons.arrow_forward_rounded,
                      onPressed: () => context.go('/signup'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    PillButton(
                      label: 'Sign in',
                      tone: PillTone.neutral,
                      glow: false,
                      onPressed: () => context.go('/login'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _ProfileBody(profile: p);
        },
      ),
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  bool _uploadingAvatar = false;
  bool _deletingAccount = false;

  Future<void> _changeAvatar() async {
    final file = await pickAvatarImage(context);
    if (file == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final url = await AvatarService.upload(file, widget.profile.id);
      if (!mounted) return;
      await ref
          .read(profileProvider.notifier)
          .update(widget.profile.copyWith(avatarUrl: url));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Couldn't update your photo — try again.")),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editNumber(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String unit,
    required num initial,
    required UserProfile Function(double value) apply,
    bool decimal = false,
  }) async {
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => _NumberEditDialog(
        title: title,
        unit: unit,
        initial: initial,
        decimal: decimal,
      ),
    );
    if (value == null || value <= 0) return;
    // Reminders that quote a target are re-registered by `ProfileNotifier
    // .update` itself, so nothing to do here — see the comment there.
    await ref.read(profileProvider.notifier).update(apply(value));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final macroSplit = _macroSplit(p);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.lg),
      children: [
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _uploadingAvatar ? null : _changeAvatar,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProfileBadge(
                      name: p.name,
                      avatarUrl: p.avatarUrl,
                      size: 110,
                      ringColor: AppColors.outlineVariant,
                    ),
                    if (_uploadingAvatar)
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: -2,
                      bottom: 2,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.background, width: 3),
                        ),
                        child: const Icon(Icons.photo_camera_rounded,
                            color: AppColors.onPrimary, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                  p.name?.trim().isNotEmpty == true
                      ? p.name!
                      : 'Proteinix User',
                  style: AppText.headlineLg()),
              const SizedBox(height: 4),
              Text(
                [
                  if (p.age != null) '${p.age} years',
                  if (p.gender != null) p.gender!,
                  if (p.goal != null) p.goal!,
                ].join(' · '),
                style: AppText.bodySm(color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Health Goals',
                style: AppText.headlineMd(color: AppColors.primary)),
            GestureDetector(
              onTap: () => context.push('/onboarding', extra: true),
              behavior: HitTestBehavior.opaque,
              child: Text('EDIT ALL',
                  style:
                      AppText.labelCaps(color: AppColors.secondary, size: 12)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.gutter,
          crossAxisSpacing: AppSpacing.gutter,
          childAspectRatio: 1.35,
          children: [
            StatTile(
              label: 'Calories',
              value: '${p.calorieGoal}',
              unit: 'kcal',
              icon: Icons.local_fire_department_rounded,
              accent: AppColors.primaryContainer,
              onEdit: () => _editNumber(
                context,
                ref,
                title: 'Daily calorie goal',
                unit: 'kcal',
                initial: p.calorieGoal,
                apply: (v) => p.copyWith(calorieGoal: v.round()),
              ),
            ),
            StatTile(
              label: 'Protein',
              value: p.proteinGoalG.round().toString(),
              unit: 'g',
              icon: Icons.egg_alt_outlined,
              accent: AppColors.secondary,
              onEdit: () => _editNumber(
                context,
                ref,
                title: 'Daily protein goal',
                unit: 'g',
                initial: p.proteinGoalG,
                apply: (v) => p.copyWith(proteinGoalG: v),
              ),
            ),
            StatTile(
              label: 'Current weight',
              value: (p.weightKg ?? 0).toStringAsFixed(1),
              unit: 'kg',
              icon: Icons.monitor_weight_outlined,
              accent: AppColors.fiberTeal,
              onEdit: () => _editNumber(
                context,
                ref,
                title: 'Current weight',
                unit: 'kg',
                initial: p.weightKg ?? 70,
                decimal: true,
                apply: (v) => p.copyWith(weightKg: v),
              ),
            ),
            StatTile(
              label: 'Macro split',
              value: macroSplit,
              icon: Icons.pie_chart_outline_rounded,
              accent: AppColors.primary,
            ),
            StatTile(
              label: 'Water',
              value: '${p.waterGoalMl}',
              unit: 'ml',
              icon: Icons.water_drop_outlined,
              accent: AppColors.water,
              onEdit: () => _editNumber(
                context,
                ref,
                title: 'Daily water goal',
                unit: 'ml',
                initial: p.waterGoalMl,
                apply: (v) => p.copyWith(waterGoalMl: v.round()),
              ),
            ),
            StatTile(
              label: 'Steps',
              value: '${p.stepsGoal}',
              icon: Icons.directions_walk_rounded,
              accent: AppColors.secondary,
              onEdit: () => _editNumber(
                context,
                ref,
                title: 'Daily step goal',
                unit: 'steps',
                initial: p.stepsGoal,
                apply: (v) => p.copyWith(stepsGoal: v.round()),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Wellness Tools',
            style: AppText.headlineMd(color: AppColors.primary)),
        const SizedBox(height: AppSpacing.sm),
        TerraListRow(
          title: 'Subscription',
          subtitle: 'Manage your Premium plan',
          icon: Icons.workspace_premium_outlined,
          iconColor: AppColors.primary,
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant),
          onTap: () => context.push('/subscription'),
        ),
        const SizedBox(height: 12),
        TerraListRow(
          title: 'Reminders',
          subtitle: 'Water and meal notifications',
          icon: Icons.notifications_active_outlined,
          iconColor: AppColors.primary,
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant),
          onTap: () => context.push('/notifications'),
        ),
        const SizedBox(height: 12),
        TerraListRow(
          title: 'Help & support',
          subtitle: 'Refunds, sign-in trouble, or report a problem',
          icon: Icons.support_agent_rounded,
          iconColor: AppColors.primary,
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant),
          onTap: () => context.push('/support'),
        ),
        const SizedBox(height: 12),
        TerraListRow(
          title: 'Diagnostics',
          subtitle: 'Recent errors captured by the app',
          icon: Icons.bug_report_outlined,
          iconColor: AppColors.onSurfaceVariant,
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant),
          onTap: () => context.push('/diagnostics'),
        ),
        const SizedBox(height: 12),
        TerraListRow(
          title: 'About & licences',
          subtitle: 'Version ${AppStrings.appVersion} · open-source licences',
          icon: Icons.info_outline_rounded,
          iconColor: AppColors.onSurfaceVariant,
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant),
          // The bundled food icons are OpenMoji (CC BY-SA 4.0), which requires
          // its attribution to be reachable from inside the app. main.dart
          // registers it; this is the only screen that opens the page.
          onTap: () => showLicensePage(
            context: context,
            applicationName: AppStrings.appFullName,
            applicationVersion: AppStrings.appVersion,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PillButton(
          label: 'Log out',
          tone: PillTone.danger,
          icon: Icons.logout_rounded,
          glow: false,
          onPressed: () {
            // Navigate first, sign out after: the flush-outbox-then-clear-
            // cache-then-two-network-calls sequence in signOut() can run a
            // few seconds on a slow connection, and awaiting it here left the
            // button looking dead — tap, then nothing on screen — until it
            // finally landed on /welcome. Nothing on that screen depends on
            // the sign-out having finished, so there's nothing to wait for.
            context.go('/welcome');
            unawaited(ref.read(profileProvider.notifier).signOut());
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: _deletingAccount
                ? null
                : () => _confirmDeleteAccount(context, ref),
            child: Text(
              _deletingAccount ? 'Deleting account…' : 'Delete account',
              style: AppText.bodySm(color: AppColors.error),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your account and everything in it — '
          'meals, logs, weight history, coach chats, photos. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await ref.read(profileProvider.notifier).deleteAccount();
      if (context.mounted) context.go('/welcome');
    } catch (_) {
      if (!context.mounted) return;
      setState(() => _deletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Couldn't delete your account. Check your connection and try again."),
        ),
      );
    }
  }

  static String _macroSplit(UserProfile p) {
    final pCal = p.proteinGoalG * 4;
    final cCal = p.carbsGoalG * 4;
    final fCal = p.fatGoalG * 9;
    final total = pCal + cCal + fCal;
    if (total <= 0) return '—';
    int pct(double v) => ((v / total) * 100).round();
    return '${pct(pCal)}/${pct(cCal)}/${pct(fCal)}';
  }
}

/// Single-value editor for weight / height / goal numbers.
///
/// Owns its controller and focus node so they live exactly as long as the
/// dialog does — the previous version created the controller in the caller and
/// disposed it the moment `showDialog` returned, i.e. while the closing dialog
/// was still building with it.
class _NumberEditDialog extends StatefulWidget {
  const _NumberEditDialog({
    required this.title,
    required this.unit,
    required this.initial,
    required this.decimal,
  });

  final String title;
  final String unit;
  final num initial;
  final bool decimal;

  @override
  State<_NumberEditDialog> createState() => _NumberEditDialogState();
}

class _NumberEditDialogState extends State<_NumberEditDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.decimal
        ? widget.initial.toStringAsFixed(1)
        : widget.initial.round().toString(),
  );
  final _node = FocusNode();

  @override
  void initState() {
    super.initState();
    // `autofocus: true` grabs focus while the dialog is still animating in, and
    // the transition finishing can drop it again — the keyboard flashes open
    // and closes. Wait for the push animation to settle, then focus once.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusWhenSettled());
  }

  void _focusWhenSettled() {
    if (!mounted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _node.requestFocus();
      return;
    }
    void onStatus(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      animation.removeStatusListener(onStatus);
      if (mounted) _node.requestFocus();
    }

    animation.addStatusListener(onStatus);
  }

  void _save() => Navigator.pop(context, double.tryParse(_ctrl.text.trim()));

  @override
  void dispose() {
    _ctrl.dispose();
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        focusNode: _node,
        keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
        inputFormatters:
            widget.decimal ? null : [FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        style: AppText.data(),
        decoration: InputDecoration(suffixText: widget.unit),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
