import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../models/food_scan_result.dart';
import '../../core/errors/ai_quota_exceeded_exception.dart';
import '../../services/gemini_vision_service.dart';
import '../../services/voice_input_service.dart';
import '../../widgets/ui/ui.dart';
import 'analysis_results_screen.dart';
import '../../core/utils/entitlement_gate.dart';

/// Hands-free meal logging: speak the meal, watch it transcribe live, then hand
/// the transcript to the same nutrition model the text and photo flows use.
class VoiceLogScreen extends ConsumerStatefulWidget {
  const VoiceLogScreen({super.key, this.mealType = 'snack'});

  final String mealType;

  @override
  ConsumerState<VoiceLogScreen> createState() => _VoiceLogScreenState();
}

class _VoiceLogScreenState extends ConsumerState<VoiceLogScreen> {
  final _voice = VoiceInputService.instance;
  final _vision = GeminiVisionService();
  final _editor = TextEditingController();

  bool _listening = false;
  bool _analyzing = false;
  double _level = 0;
  String? _error;
  FoodScanResult? _result;

  static const _tips = [
    'Two rotis with dal and a bowl of curd',
    'A hundred and fifty grams grilled chicken with rice',
    'Greek salad, hummus and a glass of buttermilk',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  @override
  void dispose() {
    _voice.cancel();
    _editor.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final reason = await _voice.prepare();
    if (mounted && reason != null) setState(() => _error = reason);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _voice.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    setState(() {
      _error = null;
      _result = null;
      _listening = true;
      _level = 0;
    });

    await _voice.start(
      onResult: (text) {
        if (!mounted) return;
        setState(() {
          _editor.text = text;
          _editor.selection =
              TextSelection.collapsed(offset: _editor.text.length);
        });
      },
      onFinalResult: (text) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _level = 0;
        });
      },
      // Android reports roughly -2..10 dB RMS; map that onto 0..1.
      onSoundLevel: (db) {
        if (!mounted) return;
        setState(() => _level = ((db + 2) / 12).clamp(0.0, 1.0));
      },
      onError: (message) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _error = message;
        });
      },
    );
  }

  Future<void> _analyze() async {
    final text = _editor.text.trim();
    if (text.isEmpty || _analyzing) return;
    // Free for the first three days, then premium. See requireEntitlement:
    // it shows the paywall itself and returns true if the user subscribes on
    // the spot, so this tap completes rather than needing to be repeated.
    if (!await requireEntitlement(context, ref)) return;

    if (_listening) await _voice.stop();
    setState(() {
      _listening = false;
      _analyzing = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await _vision.scanText(text);
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        if (result.detected && result.foodItems.isNotEmpty) {
          _result = result;
        } else {
          _error = "I couldn't pick out any food from that. "
              'Try naming the dish and a rough quantity.';
        }
      });
    } on AiQuotaExceededException catch (e) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = 'Analysis failed. Check your connection and try again.';
      });
    }
  }

  void _review() {
    final result = _result;
    if (result == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalysisResultsScreen(
          result: result,
          mealType:
              result.mealType.isNotEmpty ? result.mealType : widget.mealType,
          sourceLabel: 'Voice logged',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _editor.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: const TerraAppBar(
          title: 'Log by Voice', titleColor: AppColors.secondary),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md,
              AppSpacing.page, MediaQuery.of(context).viewInsets.bottom + 120),
          children: [
            Center(
              child: VoicePulse(
                listening: _listening,
                level: _level,
                onTap: _toggleListening,
              ),
            ),
            Center(
              child: Text(
                _listening
                    ? 'LISTENING…'
                    : hasText
                        ? 'TAP TO ADD MORE'
                        : 'TAP TO SPEAK',
                style: AppText.labelCaps(
                  color: _listening
                      ? AppColors.secondary
                      : AppColors.onSurfaceVariant,
                  size: 12,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            VoiceWaveform(listening: _listening, level: _level),
            const SizedBox(height: AppSpacing.md),
            const SectionLabel('Transcript'),
            const SizedBox(height: 10),
            TerraTextArea(
              controller: _editor,
              onChanged: (_) => setState(() {}),
              hint: _listening
                  ? 'Speak now…'
                  : 'Tap the mic, or tap here to type your meal',
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!hasText) ...[
              Text('TRY SAYING', style: AppText.labelCaps(size: 10)),
              const SizedBox(height: 8),
              ..._tips.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.graphic_eq_rounded,
                          size: 14, color: AppColors.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('"$t"',
                            style: AppText.bodySm(
                                    color: AppColors.onSurfaceVariant)
                                .copyWith(fontStyle: FontStyle.italic)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            PillButton(
              label: _analyzing ? 'Analyzing…' : 'Analyze meal',
              tone: PillTone.lime,
              icon: Icons.auto_awesome_rounded,
              loading: _analyzing,
              onPressed: hasText && !_analyzing ? _analyze : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              TerraEmptyState(
                icon: Icons.mic_off_rounded,
                title: 'Voice logging stalled',
                message: _error,
                accent: AppColors.error,
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: AppSpacing.md),
              _detected(_result!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _result == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
                child: PillButton(
                  label: 'Review & log meal',
                  trailingIcon: Icons.arrow_forward_rounded,
                  onPressed: _review,
                ),
              ),
            ),
    );
  }

  Widget _detected(FoodScanResult r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel(
          'Heard & detected',
          trailing: TerraBadge(
            label: 'AI parsed',
            icon: Icons.auto_awesome_rounded,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...r.foodItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TerraListRow(
              title: item.name,
              subtitle:
                  'Approx. ${item.calories} kcal · ${item.quantity.round()}${item.unit}',
              leading: FoodIcon(foodName: item.name, size: 48),
              trailing: const Icon(Icons.check_circle_rounded,
                  color: AppColors.secondary, size: 22),
            ),
          ),
        ),
        TerraCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          elevated: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Estimated total', style: AppText.bodyBold()),
              Text('${r.totalCalories} kcal',
                  style: AppText.data(color: AppColors.secondary)),
            ],
          ),
        ),
      ],
    );
  }
}
