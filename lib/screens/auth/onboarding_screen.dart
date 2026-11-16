import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/avatar_picker_sheet.dart';
import '../../core/utils/nutrition_calculator.dart';
import '../../core/utils/technical_issue.dart';
import '../../models/local/local_weight_log.dart';
import '../../providers/auth_provider.dart';
import '../../services/avatar_service.dart';
import '../../services/daily_mission_gate.dart';
import '../../services/local_db_service.dart';
import '../../services/notification_service.dart';
import '../../services/onboarding_draft_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';

enum WeightUnit { kg, lbs }

enum HeightUnit { cm, ft }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.isEditing = false});

  /// True when opened from Profile → "Edit all" to update an existing
  /// profile, rather than during first-time account setup. Changes how the
  /// back button and the final step behave — an edit should return to
  /// Profile, not restart the welcome flow or drop into onboarding's own
  /// post-signup routing.
  final bool isEditing;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  static const _steps = 3;
  static const _stepTitles = [
    AppStrings.personalProfile,
    '66% Complete',
    'Almost there',
  ];

  final _page = PageController();
  int _step = 0;
  bool _saving = false;

  final _name = TextEditingController();
  final _age = TextEditingController(text: '28');
  final _weight = TextEditingController(text: '70');
  final _height = TextEditingController(text: '170');
  final _targetWeight = TextEditingController();

  final _nameFocus = FocusNode();
  final _ageFocus = FocusNode();
  final _weightFocus = FocusNode();
  final _heightFocus = FocusNode();
  final _targetWeightFocus = FocusNode();

  String _gender = 'Male';
  WeightUnit _weightUnit = WeightUnit.kg;
  HeightUnit _heightUnit = HeightUnit.cm;

  String? _goal;
  String? _activity;

  String? _avatarUrl;
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    final file = await pickAvatarImage(context);
    if (file == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final url = await AvatarService.upload(file, uid);
      if (mounted) setState(() => _avatarUrl = url);
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

  @override
  void initState() {
    super.initState();
    // Step 1's Next button depends on the field contents, so rebuild as they
    // change; step 2's does too once a weight-change goal adds the target
    // weight field.
    for (final c in [_name, _age, _weight, _height, _targetWeight]) {
      c.addListener(_onFieldChanged);
    }
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.isEditing ? _prefill() : _restoreDraft());
  }

  /// True once the profile has been written, so the exit hooks below know the
  /// difference between abandoning the wizard and finishing it.
  bool _completed = false;

  /// Saves whatever has been filled in so far, and books the follow-up nudges.
  ///
  /// Called when the user leaves — the app going to the background, or backing
  /// out of step 1 — and never on keystrokes. Someone who fills all three
  /// steps in one sitting therefore never writes a draft at all: there is
  /// nothing to resume, so there is nothing to keep.
  Future<void> _saveDraft() async {
    if (widget.isEditing || _completed) return;

    final draft = OnboardingDraft(
      step: _step,
      name: _name.text,
      age: _age.text,
      weight: _weight.text,
      height: _height.text,
      targetWeight: _targetWeight.text,
      weightUnit: _weightUnit.name,
      heightUnit: _heightUnit.name,
      gender: _gender,
      goal: _goal,
      activity: _activity,
      avatarUrl: _avatarUrl,
      savedAt: DateTime.now(),
    );
    if (draft.isEmpty) return;

    final uid = SupabaseService.currentUserId;
    await OnboardingDraftService.save(draft, uid: uid);
    await NotificationService.scheduleOnboardingFollowUp();
  }

  /// Puts an abandoned run back on screen, on the step it was abandoned at.
  Future<void> _restoreDraft() async {
    final draft =
        await OnboardingDraftService.load(uid: SupabaseService.currentUserId);
    if (draft == null || !mounted) return;

    setState(() {
      if (draft.name != null) _name.text = draft.name!;
      if (draft.age != null && draft.age!.isNotEmpty) _age.text = draft.age!;
      if (draft.weight != null && draft.weight!.isNotEmpty) {
        _weight.text = draft.weight!;
      }
      if (draft.height != null && draft.height!.isNotEmpty) {
        _height.text = draft.height!;
      }
      if (draft.targetWeight != null) _targetWeight.text = draft.targetWeight!;
      _weightUnit = draft.weightUnit == WeightUnit.lbs.name
          ? WeightUnit.lbs
          : WeightUnit.kg;
      _heightUnit = draft.heightUnit == HeightUnit.ft.name
          ? HeightUnit.ft
          : HeightUnit.cm;
      if (draft.gender != null) _gender = draft.gender!;
      _goal = draft.goal;
      _activity = draft.activity;
      _avatarUrl = draft.avatarUrl;
      _step = draft.step.clamp(0, _steps - 1);
    });

    // jumpToPage, not animateToPage: the controller has no viewport until the
    // PageView has laid out, and sliding through the steps the user already
    // answered is motion that says nothing.
    if (_page.hasClients) _page.jumpToPage(_step);
  }

  /// Loads the saved profile into the form when opened from Profile → "Edit
  /// all".
  ///
  /// [isEditing] used to change only the routing at either end, so the wizard
  /// itself opened blank every time: no goal or activity selected, and name,
  /// age, weight and height sitting at the placeholder defaults 28 / 70 / 170.
  /// Someone on Build Muscle who came here to switch to Gain Weight found
  /// nothing selected — and finishing the flow wrote those defaults over their
  /// real height and weight, which then recalculated every macro target from
  /// numbers they never entered.
  ///
  /// Runs after the first frame so the provider is readable, and touches only
  /// the fields the user is about to edit.
  Future<void> _prefill() async {
    var p = ref.read(profileProvider).value;
    if (p == null) {
      // Still loading, or never pulled on this launch. Waiting beats opening
      // a blank form — that is the whole bug this method exists for.
      try {
        await ref.read(profileProvider.notifier).load();
      } catch (_) {
        // Offline with nothing cached. The defaults below are all there is.
      }
      if (!mounted) return;
      p = ref.read(profileProvider).value;
    }
    if (p == null || !mounted) return;

    setState(() {
      if (p!.name != null && p.name!.trim().isNotEmpty) _name.text = p.name!;
      if (p.age != null) _age.text = '${p.age}';
      // Always stored in metric, so the form starts in metric too rather than
      // reinterpreting 70kg as 70lbs under whatever unit was last shown.
      _weightUnit = WeightUnit.kg;
      _heightUnit = HeightUnit.cm;
      if (p.weightKg != null) _weight.text = _trim(p.weightKg!);
      if (p.heightCm != null) _height.text = _trim(p.heightCm!);
      if (p.targetWeightKg != null) {
        _targetWeight.text = _trim(p.targetWeightKg!);
      }
      // Case-insensitive: `gender` is written lowercased on save but the
      // selector's values are capitalised, so a straight assignment left the
      // segmented control matching nothing.
      final gender = p.gender?.trim().toLowerCase();
      _gender = switch (gender) {
        'male' => 'Male',
        'female' => 'Female',
        'other' => 'Other',
        // Anything else would leave the segmented control matching none of its
        // three values and so showing nothing selected.
        _ => _gender,
      };
      _goal = p.goal;
      _activity = p.activityLevel;
    });
  }

  /// "70.0" reads as unfinished in a field the user is about to edit; "70"
  /// does not. Keeps one decimal only when it carries information.
  static String _trim(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  void _onFieldChanged() {
    if ((_step == 0 || _step == 1) && mounted) setState(() {});
  }

  /// Leaving the app mid-wizard is the moment worth persisting: it is the one
  /// signal that separates "still filling this in" from "gone".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveDraft());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [_name, _age, _weight, _height, _targetWeight]) {
      c.removeListener(_onFieldChanged);
    }
    _page.dispose();
    _name.dispose();
    _age.dispose();
    _weight.dispose();
    _height.dispose();
    _targetWeight.dispose();
    _nameFocus.dispose();
    _ageFocus.dispose();
    _weightFocus.dispose();
    _heightFocus.dispose();
    _targetWeightFocus.dispose();
    super.dispose();
  }

  // ── Unit conversion ───────────────────────────────────────────────────
  double get _weightKg {
    final raw = double.tryParse(_weight.text) ?? 70;
    return _weightUnit == WeightUnit.kg ? raw : raw * 0.453592;
  }

  double get _heightCm {
    final raw = double.tryParse(_height.text) ?? 170;
    return _heightUnit == HeightUnit.cm ? raw : raw * 30.48;
  }

  /// Only 'Lose Weight' and 'Gain Weight' name a scale-weight target — the
  /// other goals (Build Muscle, Stay Active, Maintain Weight) aren't
  /// centered on a number the scale would confirm.
  bool get _needsTargetWeight =>
      _goal == 'Lose Weight' || _goal == 'Gain Weight';

  double? get _targetWeightKg {
    final raw = double.tryParse(_targetWeight.text);
    if (raw == null) return null;
    return _weightUnit == WeightUnit.kg ? raw : raw * 0.453592;
  }

  void _switchWeightUnit(WeightUnit u) {
    if (u == _weightUnit) return;
    final raw = double.tryParse(_weight.text);
    final rawTarget = double.tryParse(_targetWeight.text);
    setState(() {
      _weightUnit = u;
      if (raw != null) {
        final converted = u == WeightUnit.kg ? raw * 0.453592 : raw / 0.453592;
        _weight.text = converted.toStringAsFixed(1);
      }
      if (rawTarget != null) {
        final converted =
            u == WeightUnit.kg ? rawTarget * 0.453592 : rawTarget / 0.453592;
        _targetWeight.text = converted.toStringAsFixed(1);
      }
    });
  }

  void _switchHeightUnit(HeightUnit u) {
    if (u == _heightUnit) return;
    final raw = double.tryParse(_height.text);
    setState(() {
      _heightUnit = u;
      if (raw != null) {
        final converted = u == HeightUnit.cm ? raw * 30.48 : raw / 30.48;
        _height.text = converted.toStringAsFixed(u == HeightUnit.cm ? 0 : 1);
      }
    });
  }

  // ── Navigation ────────────────────────────────────────────────────────
  bool get _canAdvance {
    switch (_step) {
      case 0:
        return _name.text.trim().isNotEmpty &&
            (int.tryParse(_age.text) ?? 0) > 0 &&
            _weightKg > 0 &&
            _heightCm > 0;
      case 1:
        if (_goal == null) return false;
        if (_needsTargetWeight) {
          final target = _targetWeightKg;
          if (target == null || target <= 0) return false;
          // Directionally sane, not just present — a "goal" weight above
          // current weight for someone who picked Lose Weight is a typo,
          // not a target the recalibration math below can act on.
          if (_goal == 'Lose Weight' && target >= _weightKg) return false;
          if (_goal == 'Gain Weight' && target <= _weightKg) return false;
        }
        return true;
      case 2:
        return _activity != null;
      default:
        return false;
    }
  }

  void _next() {
    if (_step < _steps - 1) {
      setState(() => _step++);
      _page.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step == 0) {
      // Editing was entered via push from Profile, so there's a real
      // screen to return to — popping back to /welcome instead (the old
      // behavior, unconditional) threw the in-progress edit away and
      // dumped the user on the signed-out landing screen.
      if (widget.isEditing) {
        context.pop();
      } else {
        // Backing out of the first step is leaving, same as backgrounding the
        // app — keep the answers and book the nudges.
        unawaited(_saveDraft());
        context.go('/welcome');
      }
      return;
    }
    setState(() => _step--);
    _page.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic);
  }

  Future<void> _finish() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      context.go('/login');
      return;
    }

    final targets = NutritionCalculator.dailyTargets(
      gender: _gender,
      age: int.tryParse(_age.text) ?? 28,
      heightCm: _heightCm,
      weightKg: _weightKg,
      goal: _goal ?? 'Maintain Weight',
      activityLevel: _activity ?? 'Moderately Active',
    );

    final confirmed = await _showTargetsSheet(targets);
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await SupabaseService.client.from('profiles').upsert({
        'id': uid,
        'name':
            _name.text.trim().isEmpty ? 'Proteinix User' : _name.text.trim(),
        if (_avatarUrl != null) 'avatar_url': _avatarUrl,
        'gender': _gender.toLowerCase(),
        'age': int.tryParse(_age.text) ?? 28,
        'height_cm': _heightCm,
        'weight_kg': _weightKg,
        'target_weight_kg': _needsTargetWeight ? _targetWeightKg : null,
        'goal': _goal,
        'activity_level': _activity,
        'calorie_goal': targets['calories'],
        'protein_goal_g': targets['protein_g'],
        'carbs_goal_g': targets['carbs_g'],
        'fat_goal_g': targets['fat_g'],
        'fiber_goal_g': targets['fiber_g'],
        'water_goal_ml': targets['water_ml'],
        'steps_goal': targets['steps'],
        'sleep_goal_hrs': targets['sleep_hrs'],
        'onboarding_complete': true,
      });

      // A baseline weigh-in, once, on first-time completion only — an
      // "Edit all" pass through this same screen must not spam weight_logs
      // or reset the weekly check-in's anchor date every time a detail
      // changes.
      if (!widget.isEditing) {
        await LocalDBService.saveWeightLog(LocalWeightLog(
          id: LocalDBService.newId(),
          userId: uid,
          weightKg: _weightKg,
          date: DateTime.now(),
        ));
      }

      // The wizard is done, so the draft has nothing left to resume and the
      // nudges have nothing left to nudge about. Cleared before routing
      // onward: a draft that outlives its own completion is exactly how a
      // finished user gets dropped back into step 2 on their next launch.
      _completed = true;
      await OnboardingDraftService.clear();
      await NotificationService.cancelOnboardingFollowUp();

      await ref.read(profileProvider.notifier).load();
      if (!mounted) return;
      if (widget.isEditing) {
        // Return to Profile with the updated goals rather than routing
        // through post-signup screens meant for a brand-new account.
        context.pop();
        return;
      }
      final showMission = await DailyMissionGate.shouldShow();
      if (!mounted) return;
      context.go(showMission ? '/daily-mission' : '/home');
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showTechnicalIssue(
        context,
        action: 'save your profile',
        reportContext: 'onboarding_save_profile',
        error: e,
        stack: s,
        onRetry: _finish,
      );
    }
  }

  Future<bool?> _showTargetsSheet(Map<String, num> t) {
    return showModalBottomSheet<bool>(
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
            children: [
              const SectionLabel('Your daily targets'),
              const SizedBox(height: AppSpacing.sm),
              Text('${t['calories']}',
                  style: AppText.display(color: AppColors.primary)),
              Text('KCAL PER DAY', style: AppText.labelCaps(size: 11)),
              const SizedBox(height: AppSpacing.md),
              const Divider(color: AppColors.outline),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _target('Protein', '${(t['protein_g'] ?? 0).round()}g',
                      AppColors.protein),
                  _target('Carbs', '${(t['carbs_g'] ?? 0).round()}g',
                      AppColors.carbs),
                  _target(
                      'Fats', '${(t['fat_g'] ?? 0).round()}g', AppColors.fat),
                  _target('Fiber', '${(t['fiber_g'] ?? 0).round()}g',
                      AppColors.fiber),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _target('Water', '${t['water_ml']}ml', AppColors.water),
                  _target('Steps', '${t['steps']}', AppColors.secondary),
                  _target('Sleep', '${t['sleep_hrs']}h', AppColors.tertiary),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              PillButton(
                label: 'Start tracking',
                trailingIcon: Icons.arrow_forward_rounded,
                onPressed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Adjust my answers'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _target(String label, String value, Color color) => Column(
        children: [
          Text(value, style: AppText.data(color: color)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(), style: AppText.labelCaps(size: 9)),
        ],
      );

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Most entry points reach this screen via `context.go(...)`, which
      // leaves nothing on the Navigator stack for system back to pop —
      // routing it through the same _back() the on-screen arrow uses keeps
      // both consistent (step-by-step back, and edit-mode popping to
      // Profile instead of restarting the welcome flow).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: TerraAppBar(
          title: 'Proteinix Wellness',
          titleColor: AppColors.secondary,
          onBack: _back,
        ),
        resizeToAvoidBottomInset: true,
        body: DismissKeyboard(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, AppSpacing.sm, AppSpacing.page, 0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('STEP ${_step + 1} OF $_steps',
                            style: AppText.labelCaps(
                                color: AppColors.secondary, size: 11)),
                        Text(_stepTitles[_step],
                            style: AppText.labelCaps(
                                color: AppColors.onSurface, size: 12)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearMeter(value: (_step + 1) / _steps, glow: true),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _page,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_stepProfile(), _stepGoal(), _stepActivity()],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                      AppSpacing.xs, AppSpacing.page, AppSpacing.sm),
                  child: Column(
                    children: [
                      PillButton(
                        label: _step == _steps - 1
                            ? AppStrings.completeProfile
                            : 'Next',
                        tone: PillTone.lime,
                        trailingIcon: _step == _steps - 1
                            ? Icons.celebration_outlined
                            : Icons.arrow_forward_rounded,
                        loading: _saving,
                        onPressed: _canAdvance && !_saving ? _next : null,
                      ),
                      if (_step == _steps - 1) ...[
                        const SizedBox(height: 10),
                        Text(
                          AppStrings.onboardingTerms.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: AppText.labelCaps(size: 9),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1: personal profile ──────────────────────────────────────────
  Widget _stepProfile() {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      // No viewInsets here — `resizeToAvoidBottomInset` already lifts this
      // clear of the keyboard, and reading the inset rebuilt the whole step on
      // every frame of the keyboard animation.
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.md),
      children: [
        Center(
          child: GestureDetector(
            onTap: _uploadingAvatar ? null : _changeAvatar,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ProfileBadge(
                  name: _name.text,
                  avatarUrl: _avatarUrl,
                  size: 96,
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
                          width: 24,
                          height: 24,
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
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.background, width: 3),
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        color: AppColors.onPrimary, size: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TerraCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TerraField(
                controller: _name,
                focusNode: _nameFocus,
                nextFocus: _ageFocus,
                label: 'Full name',
                hint: 'E.g. Rowan Green',
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TerraField(
                      controller: _age,
                      focusNode: _ageFocus,
                      nextFocus: _weightFocus,
                      label: 'Age',
                      hint: '28',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GENDER', style: AppText.labelCaps(size: 11)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 56,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SegmentedPill<String>(
                              values: const ['Male', 'Female', 'Other'],
                              selected: _gender,
                              compact: true,
                              labelBuilder: (g) => g.substring(0, 1),
                              onChanged: (g) => setState(() => _gender = g),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _unitRow(
                label: 'Current weight',
                toggle: SegmentedPill<WeightUnit>(
                  values: WeightUnit.values,
                  selected: _weightUnit,
                  compact: true,
                  labelBuilder: (u) => u.name,
                  onChanged: _switchWeightUnit,
                ),
              ),
              const SizedBox(height: 8),
              TerraField(
                controller: _weight,
                focusNode: _weightFocus,
                nextFocus: _heightFocus,
                hint: '0.0',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,4}\.?\d{0,2}')),
                ],
                trailingText: _weightUnit.name,
              ),
              const SizedBox(height: AppSpacing.md),
              _unitRow(
                label: 'Height',
                toggle: SegmentedPill<HeightUnit>(
                  values: HeightUnit.values,
                  selected: _heightUnit,
                  compact: true,
                  labelBuilder: (u) => u.name,
                  onChanged: _switchHeightUnit,
                ),
              ),
              const SizedBox(height: 8),
              TerraField(
                controller: _height,
                focusNode: _heightFocus,
                hint: '0',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,4}\.?\d{0,2}')),
                ],
                trailingText: _heightUnit.name,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TerraCard(
                padding: const EdgeInsets.all(AppSpacing.sm),
                color:
                    AppColors.onSecondaryFixedVariant.withValues(alpha: 0.35),
                borderColor: AppColors.secondary.withValues(alpha: 0.25),
                child: Text(
                  'Embrace your natural rhythm.',
                  style: AppText.body(color: AppColors.onSurface)
                      .copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(
              child: TerraCard(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Center(
                  child: Icon(Icons.eco_rounded,
                      color: AppColors.secondary, size: 32),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _unitRow({required String label, required Widget toggle}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child:
                Text(label.toUpperCase(), style: AppText.labelCaps(size: 11)),
          ),
          toggle,
        ],
      );

  // ── Step 2: primary goal ──────────────────────────────────────────────
  Widget _stepGoal() {
    // Gain Weight was missing: NutritionCalculator had a branch for it that
    // nothing could ever select, so an underweight user had to pick Build
    // Muscle and got a 10% surplus where they need 15%.
    const goals = [
      ('Lose Weight', Icons.trending_down_rounded),
      ('Gain Weight', Icons.trending_up_rounded),
      ('Build Muscle', Icons.fitness_center_rounded),
      ('Stay Active', Icons.directions_run_rounded),
      ('Maintain Weight', Icons.balance_rounded),
    ];

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      // No viewInsets here — `resizeToAvoidBottomInset` already lifts this
      // clear of the keyboard, and reading the inset rebuilt the whole step on
      // every frame of the keyboard animation.
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.md),
      children: [
        Text(
          AppStrings.goalQuestion,
          textAlign: TextAlign.center,
          style: AppText.display().copyWith(fontSize: 30, height: 1.2),
        ),
        const SizedBox(height: 12),
        Text(
          'Select the path that feels most resonant with your journey today.',
          textAlign: TextAlign.center,
          style: AppText.body(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        ...goals.map(
          (g) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: OptionTile(
              label: g.$1,
              icon: g.$2,
              selected: _goal == g.$1,
              onTap: () => setState(() => _goal = g.$1),
            ),
          ),
        ),
        if (_needsTargetWeight) ...[
          const SizedBox(height: AppSpacing.sm),
          TerraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('CURRENT WEIGHT', style: AppText.labelCaps(size: 11)),
                    // Pulled from step 1, never re-asked — the user already
                    // told us this once.
                    Text(
                      '${_weight.text.isEmpty ? '—' : _weight.text} ${_weightUnit.name}',
                      style: AppText.bodyBold(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TerraField(
                  controller: _targetWeight,
                  focusNode: _targetWeightFocus,
                  label:
                      _goal == 'Lose Weight' ? 'Goal weight' : 'Target weight',
                  hint: '0.0',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,4}\.?\d{0,2}')),
                  ],
                  trailingText: _weightUnit.name,
                ),
                if (_targetWeight.text.isNotEmpty && !_canAdvance) ...[
                  const SizedBox(height: 6),
                  Text(
                    _goal == 'Lose Weight'
                        ? 'Should be lower than your current weight.'
                        : 'Should be higher than your current weight.',
                    style: AppText.bodySm(color: AppColors.tertiary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 3: activity level ────────────────────────────────────────────
  Widget _stepActivity() {
    const levels = [
      (
        'Sedentary',
        'Spend most of the day sitting, little to no exercise, typical office job life.'
      ),
      (
        'Lightly Active',
        'Light exercise or sports 1-3 days a week, or significant daily walking.'
      ),
      (
        'Moderately Active',
        'Moderate exercise or sports 3-5 days a week. Active lifestyle.'
      ),
      (
        'Very Active',
        'Hard exercise 6-7 days a week, or a physically demanding job.'
      ),
    ];

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      // No viewInsets here — `resizeToAvoidBottomInset` already lifts this
      // clear of the keyboard, and reading the inset rebuilt the whole step on
      // every frame of the keyboard animation.
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.md),
      children: [
        Text(AppStrings.activityQuestion,
            style: AppText.display().copyWith(fontSize: 28, height: 1.2)),
        const SizedBox(height: 10),
        Text(
          'This helps us calculate your daily energy needs and personalize your wellness journey.',
          style: AppText.body(color: AppColors.onSurfaceVariant)
              .copyWith(height: 1.5),
        ),
        const SizedBox(height: AppSpacing.md),
        ...levels.map(
          (l) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: RadioOptionCard(
              title: l.$1,
              description: l.$2,
              selected: _activity == l.$1,
              onTap: () => setState(() => _activity = l.$1),
            ),
          ),
        ),
      ],
    );
  }
}
