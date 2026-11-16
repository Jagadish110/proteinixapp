import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';
import 'auth_shell.dart';

/// Shown right after email/password sign-up when Supabase requires the
/// address to be confirmed before it issues a session.
///
/// Tapping the link in that email opens the app via the same
/// `io.supabase.proteinix://login-callback/` deep link already used for Google
/// sign-in — the listener in app.dart picks that up, waits for the new
/// session, and routes on to onboarding automatically. This screen just
/// holds the user here with a clear "check your inbox" message and a resend
/// option while that happens; it doesn't need its own redirect logic.
class EmailConfirmationScreen extends StatefulWidget {
  const EmailConfirmationScreen({super.key, required this.email});

  final String email;

  @override
  State<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState extends State<EmailConfirmationScreen> {
  static const _cooldownSeconds = 45;
  static const _redirectTo = 'io.supabase.proteinix://login-callback/';

  bool _resending = false;
  bool _sentAgain = false;
  int _cooldown = 0;
  Timer? _timer;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = _cooldownSeconds);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _resend() async {
    if (_resending || _cooldown > 0) return;
    setState(() {
      _resending = true;
      _error = null;
      _sentAgain = false;
    });
    try {
      await SupabaseService.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
        emailRedirectTo: _redirectTo,
      );
      if (!mounted) return;
      setState(() => _sentAgain = true);
      _startCooldown();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't resend — try again in a moment.");
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Check your\ninbox',
      subtitle: 'One more step before you can sign in.',
      onBack: () => context.go('/login'),
      footer: AuthFooter(
        question: 'Wrong email?',
        action: 'Start over',
        onTap: () => context.go('/signup'),
      ),
      children: [
        const Center(
          child: IconBubble(
            icon: Icons.mark_email_read_outlined,
            color: AppColors.secondary,
            size: 64,
            tinted: true,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'We sent a confirmation link to',
          textAlign: TextAlign.center,
          style: AppText.body(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(widget.email,
            textAlign: TextAlign.center, style: AppText.bodyBold()),
        const SizedBox(height: 6),
        Text(
          "Tap the link to activate your account — you'll land right back "
          'in the app.',
          textAlign: TextAlign.center,
          style: AppText.bodySm(color: AppColors.onSurfaceVariant),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          AuthErrorBanner(message: _error!),
        ] else if (_sentAgain) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Confirmation email sent again.',
              textAlign: TextAlign.center,
              style: AppText.bodySm(color: AppColors.secondary)),
        ],
        const SizedBox(height: AppSpacing.md),
        PillButton(
          label: _cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Resend email',
          tone: PillTone.outline,
          icon: Icons.refresh_rounded,
          glow: false,
          loading: _resending,
          onPressed: (_resending || _cooldown > 0) ? null : _resend,
        ),
      ],
    );
  }
}
