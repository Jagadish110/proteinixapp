import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/daily_log_provider.dart';
import '../../core/errors/ai_quota_exceeded_exception.dart';
import '../../services/gemini_service.dart';
import '../../widgets/ui/ui.dart';
import '../../core/utils/coach_nudge.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/entitlement_gate.dart';
import '../../services/plan_limits.dart';
import '../../core/utils/require_account.dart';

class _ChatMessage {
  _ChatMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}

class AiCoachScreen extends ConsumerStatefulWidget {
  const AiCoachScreen({super.key});

  @override
  ConsumerState<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends ConsumerState<AiCoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _gemini = GeminiService();

  final List<_ChatMessage> _messages = [];
  bool _thinking = false;

  static const _prompts = [
    (Icons.bedtime_outlined, 'Analyze my sleep'),
    (Icons.restaurant_rounded, 'Meal ideas'),
    (Icons.bolt_rounded, 'Protein gap'),
    (Icons.local_fire_department_rounded, 'Am I on track?'),
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _newChat() {
    if (_thinking || _messages.isEmpty) return;
    setState(() => _messages.clear());
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _thinking) return;
    // Before the entitlement check, not after: someone with no account has no
    // subscription to evaluate, and asking them to pay before asking them to
    // sign up is the wrong order.
    if (!await requireAccount(context, action: 'chat with your coach')) return;
    if (!mounted) return;
    // A Pro feature. See requireEntitlement: it shows the paywall itself and
    // returns true if the user subscribes on the spot, so this tap completes
    // rather than needing to be repeated.
    if (!await requireEntitlement(context, ref, feature: ProFeature.coach)) {
      return;
    }

    // Everyone gets the same daily ceiling on coach messages, Pro included.
    // Said in the chat rather than a dialog, so the conversation so far stays
    // on screen and the user can still read the last answer.
    if (await PlanLimits.coachMessagesLeft() <= 0) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(text: text, fromUser: true));
        _messages.add(_ChatMessage(
          fromUser: false,
          text: "That's today's ${PlanLimits.coachMessagesPerDay} coach "
              'messages. I will be back tomorrow — your nudge above keeps '
              'updating in the meantime.',
        ));
      });
      _input.clear();
      _scrollToBottom();
      return;
    }
    if (!mounted) return;

    setState(() {
      _messages.add(_ChatMessage(text: text, fromUser: true));
      _thinking = true;
    });
    _input.clear();
    _scrollToBottom();

    final profile = ref.read(profileProvider).value;
    if (profile == null) {
      setState(() {
        _thinking = false;
        _messages.add(_ChatMessage(
          fromUser: false,
          text: 'I need your profile before I can give tailored advice. '
              'Finish onboarding and try again.',
        ));
      });
      return;
    }

    final date = ref.read(selectedDateProvider);
    final log = ref.read(dailyLogProvider(date));
    final meals = ref.read(mealsForDateProvider(date));

    try {
      final reply = await _gemini.sendMessage(
        profile: profile,
        log: log,
        meals: meals,
        language: profile.language,
        history: _messages
            .take(_messages.length - 1)
            .map((m) => (role: m.fromUser ? 'user' : 'model', text: m.text))
            .toList(),
        userMessage: text,
      );
      // Only a message that was actually answered counts against the day.
      await PlanLimits.recordCoachMessage();
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _messages.add(_ChatMessage(text: reply, fromUser: false));
      });
    } on AiQuotaExceededException catch (e) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _messages.add(_ChatMessage(fromUser: false, text: e.message));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _messages.add(_ChatMessage(
          fromUser: false,
          text: "I couldn't reach the coach service just now. "
              'Check your connection and try again.',
        ));
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final started = _messages.isNotEmpty;

    // Gemini is the one thing here that genuinely can't run offline. Everything
    // else in the app reads from Hive, so this is a per-screen gate rather than
    // anything global.
    final online = ref.watch(isOnlineProvider);
    if (!online) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(false),
              // The nudge is arithmetic on local data, so it is the one part
              // of this tab that still works with no connection.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, AppSpacing.xs, AppSpacing.page, 0),
                child: _nudgeCard(askable: false),
              ),
              const Expanded(
                child: OfflineAIWidget(featureName: 'AI Coach'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      // The composer owns the keyboard inset outright — see _Composer.
      //
      // Letting Scaffold resize as well meant the inset was subtracted twice:
      // once here and once by the navigation shell this tab lives inside, which
      // stranded the composer in the middle of the screen with a large gap
      // above the keyboard. One place applies it, so it can't double-count.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _topBar(started),
            Expanded(child: started ? _conversation() : _emptyState()),
            _Composer(
              controller: _input,
              onSend: () => _send(_input.text),
              onSubmitted: _send,
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(bool started) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xs),
      child: Row(
        children: [
          const IconBubble(
            icon: Icons.smart_toy_rounded,
            color: AppColors.secondary,
            size: 36,
            tinted: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Proteinix Coach', style: AppText.headlineMd()),
          ),
          if (started)
            CircleIconButton(
              icon: Icons.add_comment_outlined,
              background: AppColors.surfaceContainer,
              onTap: _newChat,
            ),
        ],
      ),
    );
  }

  /// Today's nudge — the main thing this tab is for.
  ///
  /// Rebuilt from the same providers the dashboard reads, so logging a meal
  /// changes it immediately. [askable] is false offline, where the follow-up
  /// question would have nowhere to go.
  Widget _nudgeCard({bool askable = true}) {
    final profile = ref.watch(profileProvider).value;
    if (profile == null) return const SizedBox.shrink();
    // Always today, whatever day the dashboard happens to be showing — a
    // nudge about last Tuesday is not something anyone can act on.
    final today = AppDateUtils.toDateOnly(DateTime.now());
    final log = ref.watch(dailyLogProvider(today));
    final nudge = CoachNudge.forToday(profile, log, DateTime.now());

    final (icon, color) = switch (nudge.kind) {
      CoachNudgeKind.protein => (Icons.bolt_rounded, AppColors.primary),
      CoachNudgeKind.calories => (
          Icons.local_fire_department_rounded,
          AppColors.tertiary
        ),
      CoachNudgeKind.water => (Icons.water_drop_rounded, AppColors.secondary),
      CoachNudgeKind.start => (Icons.restaurant_rounded, AppColors.primary),
      CoachNudgeKind.onTrack => (
          Icons.check_circle_rounded,
          AppColors.secondary
        ),
    };

    return TerraCard(
      borderColor: color.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBubble(icon: icon, color: color, size: 40, tinted: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("TODAY'S NUDGE",
                        style: AppText.labelCaps(
                            color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(nudge.headline, style: AppText.headlineMd()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(nudge.body, style: AppText.body()),
          if (askable) ...[
            const SizedBox(height: AppSpacing.sm),
            PillButton(
              label: 'Ask the coach about this',
              icon: Icons.auto_awesome_rounded,
              height: 48,
              glow: false,
              onPressed: _thinking ? null : () => _send(nudge.followUp),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _nudgeCard(),
          const SizedBox(height: AppSpacing.lg),
          Text('Or ask anything',
              textAlign: TextAlign.center, style: AppText.headlineMd()),
          const SizedBox(height: 8),
          Text(
            "Macros, hydration, sleep or what to eat next — I can see "
            "today's numbers.",
            textAlign: TextAlign.center,
            style: AppText.body(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _prompts
                .map((p) => MiniPill(
                      label: p.$2,
                      icon: p.$1,
                      background: AppColors.surfaceContainer,
                      onTap: () => _send(p.$2),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _conversation() {
    return ListView.builder(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.sm),
      itemCount: _messages.length + (_thinking ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) return const _TypingRow();
        return _Bubble(message: _messages[i]);
      },
    );
  }
}

/// The chat input row. Kept as its own widget so that the keyboard-inset read
/// below only rebuilds this strip, never the TextField's ancestors.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    // This widget lifts itself over the keyboard: its parent Scaffold has
    // resizeToAvoidBottomInset off, so the full inset is applied here and
    // nowhere else. Reading it in this small leaf also means the chat above
    // doesn't rebuild on every frame of the keyboard animation.
    //
    // Keyboard down, the padding is instead the nav bar's clearance, since the
    // floating nav bar overlaps the bottom of this tab.
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = insets > 0
        ? insets + AppSpacing.xs
        : MediaQuery.paddingOf(context).bottom + 92;

    return Container(
      padding:
          EdgeInsets.fromLTRB(AppSpacing.page, 10, AppSpacing.page, bottom),
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: AppText.body(),
              cursorColor: AppColors.primary,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: onSubmitted,
              decoration: const InputDecoration(
                hintText: 'Message your AI Coach…',
                fillColor: AppColors.surfaceContainerLow,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow:
                    AppColors.glow(AppColors.primary, blur: 18, opacity: 0.35),
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: AppColors.onPrimary, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ChatGPT-style turn: user messages sit in a plain rounded bubble on the
/// right; assistant replies are unbounded full-width text on the left with a
/// small avatar, not a bubble — easier to read for long coaching replies.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: AppRadius.xlR,
          ),
          child: Text(
            message.text,
            style: AppText.body().copyWith(height: 1.5, fontSize: 15),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconBubble(
            icon: Icons.smart_toy_rounded,
            color: AppColors.secondary,
            size: 28,
            tinted: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                message.text,
                style: AppText.body().copyWith(height: 1.55, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three-dot "typing" indicator shown in place of the next assistant turn
/// while a reply is in flight.
class _TypingRow extends StatefulWidget {
  const _TypingRow();

  @override
  State<_TypingRow> createState() => _TypingRowState();
}

class _TypingRowState extends State<_TypingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconBubble(
            icon: Icons.smart_toy_rounded,
            color: AppColors.secondary,
            size: 28,
            tinted: true,
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, _dot),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(int i) {
    final t = (_ctrl.value - i * 0.2) % 1.0;
    final opacity = 0.25 + 0.75 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.onSurfaceVariant,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
