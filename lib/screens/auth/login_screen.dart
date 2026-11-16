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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.client.auth
          .signInWithPassword(email: _email.text.trim(), password: _pass.text);
      // A real account supersedes looking around, so the flag goes with it —
      // otherwise signing out later would drop straight back into guest mode
      // rather than the welcome screen.
      await GuestMode.disable();
      if (mounted) context.go('/home');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not sign in. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Native account picker rather than a browser hand-off. A dismissed picker
  /// returns false and is left silent — cancelling isn't an error.
  ///
  /// Navigation is explicit here: nothing in the router redirects on auth, and
  /// unlike the OAuth flow this replaced there is no deep link to trigger it.
  Future<void> _google() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (await GoogleAuthService.signIn()) {
        await GuestMode.disable();
        final route = await postSignInRoute();
        if (mounted) context.go(route);
        return;
      }
    } on GoogleAuthException catch (e) {
      setState(() => _error = e.message);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not sign in. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Sends the reset link, asking for the address if the field is empty.
  ///
  /// Prefilled from whatever has already been typed, so the common case —
  /// entering an email, then realising the password is gone — is one tap.
  Future<void> _reset() async {
    final entered = await _askResetEmail(_email.text.trim());
    if (entered == null || !mounted) return;

    setState(() => _error = null);
    try {
      await SupabaseService.client.auth.resetPasswordForEmail(entered);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset link sent to $entered. Check your inbox.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't send the reset link. Try again.");
      }
    }
  }

  Future<String?> _askResetEmail(String initial) {
    final controller = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.page,
          right: AppSpacing.page,
          bottom: MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              AppSpacing.md,
        ),
        child: TerraCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reset your password', style: AppText.headlineMd()),
              const SizedBox(height: 6),
              Text(
                "We'll email you a link to set a new one.",
                style: AppText.body(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              TerraField(
                controller: controller,
                label: AppStrings.email,
                hint: 'name@example.com',
                icon: Icons.mail_outline_rounded,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
              ),
              const SizedBox(height: AppSpacing.md),
              PillButton(
                label: 'Send reset link',
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.contains('@')) Navigator.pop(ctx, value);
                },
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Welcome back',
      subtitle: 'Pick up where your rhythm left off.',
      onBack: () => context.go('/welcome'),
      footer: AuthFooter(
        question: "Don't have an account?",
        action: AppStrings.signUp,
        onTap: () => context.go('/signup'),
      ),
      children: [
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
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          textCapitalization: TextCapitalization.none,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _login(),
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _reset,
            child: Text(AppStrings.forgotPassword,
                style: AppText.bodyBold(color: AppColors.primary)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          AuthErrorBanner(message: _error!),
        ],
        const SizedBox(height: AppSpacing.sm),
        PillButton(
          label: AppStrings.signIn,
          loading: _loading,
          onPressed: _loading ? null : _login,
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
