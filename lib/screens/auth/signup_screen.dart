import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../services/auth_routing.dart';
import '../../services/google_auth_service.dart';
import '../../services/guest_mode.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';
import 'auth_shell.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupState();
}

class _SignupState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _nameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _nameFocus.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (_pass.text.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }
    setState(() => _loading = true);
    try {
      final email = _email.text.trim();
      final res = await SupabaseService.client.auth.signUp(
        email: email,
        password: _pass.text,
        data: {'name': _name.text.trim()},
        emailRedirectTo: 'io.supabase.proteinix://login-callback/',
      );
      await GuestMode.disable();
      if (!mounted) return;
      // A null session means Supabase requires the address to be confirmed
      // before it'll issue one — send them to wait for that instead of
      // straight to onboarding, where every Supabase call would just fail
      // with no session to authenticate them.
      if (res.session == null) {
        context.go('/confirm-email', extra: email);
      } else {
        context.go('/onboarding');
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Could not create your account. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Same native picker as sign-in — with Google there is no separate "create
  /// account" step, the first successful token just creates the Supabase user.
  /// [postSignInRoute] is what sends a brand-new account into onboarding.
  Future<void> _google() async {
    setState(() => _loading = true);
    try {
      if (await GoogleAuthService.signIn()) {
        await GuestMode.disable();
        final route = await postSignInRoute();
        if (mounted) context.go(route);
        return;
      }
    } on GoogleAuthException catch (e) {
      _showError(e.message);
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Could not sign up. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Errors as a transient popup rather than a banner pinned in the layout —
  /// a wordy server message (Supabase's password-policy text is the worst
  /// offender: it spells out the entire allowed character set) used to sit
  /// permanently in the form, pushing the submit button down and outliving
  /// its relevance. A snackbar says it once and gets out of the way.
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.errorContainer,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.onErrorContainer, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message,
                    style: AppText.bodySm(color: AppColors.onErrorContainer)),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Create your\naccount',
      subtitle: 'Join our community of wellness.',
      onBack: () => context.go('/welcome'),
      footer: AuthFooter(
        question: 'Already have an account?',
        action: AppStrings.signIn,
        onTap: () => context.go('/login'),
      ),
      children: [
        TerraField(
          controller: _name,
          focusNode: _nameFocus,
          nextFocus: _emailFocus,
          label: 'Full Name',
          hint: 'E.g. Rowan Green',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: AppSpacing.sm),
        TerraField(
          controller: _email,
          focusNode: _emailFocus,
          nextFocus: _passFocus,
          label: AppStrings.email,
          hint: 'name@example.com',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
        ),
        const SizedBox(height: AppSpacing.sm),
        TerraField(
          controller: _pass,
          focusNode: _passFocus,
          label: AppStrings.password,
          hint: 'At least 6 characters',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          textCapitalization: TextCapitalization.none,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _signup(),
          suffix: IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        PillButton(
          label: AppStrings.createAccount,
          loading: _loading,
          onPressed: _loading ? null : _signup,
        ),
        const SizedBox(height: AppSpacing.md),
        const AuthDivider(),
        const SizedBox(height: AppSpacing.md),
        PillButton(
          label: AppStrings.continueWithGoogle,
          tone: PillTone.neutral,
          leading: SvgPicture.asset('assets/icons/google_logo.svg'),
          glow: false,
          onPressed: _google,
        ),
      ],
    );
  }
}
