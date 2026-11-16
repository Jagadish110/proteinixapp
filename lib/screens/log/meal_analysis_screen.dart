import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/image_compressor.dart';
import '../../core/errors/ai_quota_exceeded_exception.dart';
import '../../services/gemini_vision_service.dart';
import '../../services/voice_input_service.dart';
import '../../providers/meal_schedule_provider.dart';
import '../../services/meal_schedule_service.dart';
import '../../widgets/ui/ui.dart';
import 'analysis_results_screen.dart';
import '../../services/plan_limits.dart';
import '../../core/utils/entitlement_gate.dart';

/// Confirmation step between capture and analysis.
///
/// The captured plate is shown large so the user can judge the shot, and any
/// extra detail they add (weights, ingredients) is fed to the vision model as
/// context for a much tighter portion estimate.
class MealAnalysisScreen extends ConsumerStatefulWidget {
  const MealAnalysisScreen({
    super.key,
    required this.image,
    required this.mealType,
  });

  final File image;
  final String mealType;

  @override
  ConsumerState<MealAnalysisScreen> createState() => _MealAnalysisScreenState();
}

class _MealAnalysisScreenState extends ConsumerState<MealAnalysisScreen> {
  final _hint = TextEditingController();
  final _vision = GeminiVisionService();
  final _voice = VoiceInputService.instance;

  late String _mealType = widget.mealType;
  bool _analyzing = false;
  String? _error;

  bool _listening = false;
  double _level = 0;

  /// What was already typed when dictation started.
  ///
  /// The recogniser reports a running transcript that *replaces* itself as it
  /// refines, so appending each partial would stutter the same words into the
  /// box. Rebuilding from this fixed prefix every time keeps the field equal to
  /// "what they typed" + "what they have said so far", and makes dictating
  /// twice add to the note instead of overwriting it.
  String _dictationBase = '';

  @override
  void dispose() {
    _voice.cancel();
    _hint.dispose();
    super.dispose();
  }

  /// Dictate the weights instead of typing them.
  ///
  /// Spoken straight into the same hint the vision model already receives —
  /// saying "two hundred grams of rice" is markedly faster than typing it, and
  /// the portion estimate is only as good as this detail.
  Future<void> _toggleDictation() async {
    if (_listening) {
      await _voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final reason = await _voice.prepare();
    if (reason != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(reason)));
      }
      return;
    }

    _dictationBase = _hint.text.trimRight();
    if (!mounted) return;
    setState(() {
      _listening = true;
      _level = 0;
    });

    await _voice.start(
      onResult: (transcript) {
        if (!mounted) return;
        final joined =
            _dictationBase.isEmpty ? transcript : '$_dictationBase $transcript';
        _hint.value = TextEditingValue(
          text: joined,
          // Caret parked at the end, so carrying on by keyboard appends rather
          // than dropping the cursor back where it was before dictation.
          selection: TextSelection.collapsed(offset: joined.length),
        );
      },
      onFinalResult: (_) {
        if (mounted) setState(() => _listening = false);
      },
      onSoundLevel: (l) {
        if (mounted) setState(() => _level = l);
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _listening = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  Future<void> _analyze() async {
    if (_analyzing) return;
    // Three free scans a day, unlimited on Pro. See requireEntitlement: it shows the paywall itself and
    // returns true if the user subscribes on the spot, so this tap completes
    // rather than needing to be repeated.
    if (!await requireEntitlement(context, ref, feature: ProFeature.photoScan)) {
      return;
    }
    setState(() {
      _analyzing = true;
      _error = null;
    });

    try {
      final bytes = await ImageCompressor.compress(widget.image);
      final hint = _hint.text.trim();
      final result =
          await _vision.scanImage(bytes, userHint: hint.isEmpty ? null : hint);
      if (!mounted) return;
      setState(() => _analyzing = false);

      if (!result.detected || result.foodItems.isEmpty) {
        setState(() => _error =
            "The AI couldn't identify any food here. Retake the photo closer, "
                'or describe the dish in the box above and try again.');
        return;
      }

      // Counted only now, once there is a result worth having: a failed
      // analysis or an empty plate must not cost one of the day's free scans.
      await PlanLimits.recordScan();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AnalysisResultsScreen(
            result: result,
            mealType: _mealType,
            image: widget.image,
          ),
        ),
      );
    } on AiQuotaExceededException catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = 'Analysis failed. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: TerraAppBar(
        title: 'Proteinix',
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: TextButton.icon(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.refresh_rounded,
                size: 18, color: AppColors.secondary),
            label: Text('RETAKE',
                style: AppText.labelCaps(color: AppColors.secondary, size: 11)),
          ),
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: DismissKeyboard(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm,
              AppSpacing.page, 120 + MediaQuery.of(context).viewInsets.bottom),
          children: [
            ClipRRect(
              borderRadius: AppRadius.cardR,
              child: Stack(
                children: [
                  Image.file(widget.image,
                      width: double.infinity, height: 300, fit: BoxFit.cover),
                  const Positioned(
                    left: 12,
                    bottom: 12,
                    child: TerraBadge(
                      label: 'Ready to analyze',
                      color: AppColors.secondary,
                      filled: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Describe your meal', style: AppText.headlineLg()),
            const SizedBox(height: 8),
            Text(
              'Adding details about weight or ingredients helps our AI provide a '
              'more accurate nutritional breakdown.',
              style: AppText.body(color: AppColors.onSurfaceVariant)
                  .copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            TerraTextArea(
              controller: _hint,
              hint: _listening
                  ? 'Listening… say the weights, e.g. "two hundred grams of rice"'
                  : 'e.g. 150g of brown rice, 100g of roasted sweet potatoes, '
                      'and a handful of baby spinach…',
            ),
            const SizedBox(height: 10),
            // Speaking the weights beats typing them, and this is the one field
            // where the detail directly decides how good the estimate is.
            Row(
              children: [
                GestureDetector(
                  onTap: _analyzing ? null : _toggleDictation,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _listening
                          ? AppColors.primary.withValues(alpha: 0.16)
                          : AppColors.surfaceContainerHigh,
                      borderRadius: AppRadius.pill,
                      border: Border.all(
                        color: _listening
                            ? AppColors.primary
                            : AppColors.outline.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _listening ? Icons.stop_rounded : Icons.mic_rounded,
                          size: 18,
                          color: _listening
                              ? AppColors.primary
                              : AppColors.onSurface,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _listening ? 'Stop' : 'Speak the details',
                          style: AppText.labelCaps(
                            size: 11,
                            color: _listening
                                ? AppColors.primary
                                : AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_listening) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: VoiceWaveform(listening: _listening, level: _level),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionLabel('Meal type'),
            const SizedBox(height: 10),
            SegmentedPill<String>(
              values: [for (final s in ref.watch(mealScheduleProvider)) s.key],
              selected: _mealType,
              activeColor: AppColors.primary,
              activeTextColor: AppColors.onPrimary,
              labelBuilder: (t) => MealScheduleService.labelFor(
                  ref.read(mealScheduleProvider), t),
              onChanged: (t) => setState(() => _mealType = t),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              TerraEmptyState(
                icon: Icons.no_food_rounded,
                title: 'No food detected',
                message: _error,
                accent: AppColors.error,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
          child: PillButton(
            label: _analyzing ? 'Analyzing your plate…' : 'Analyze with AI',
            icon: Icons.auto_awesome_rounded,
            loading: _analyzing,
            onPressed: _analyzing ? null : _analyze,
          ),
        ),
      ),
    );
  }
}
