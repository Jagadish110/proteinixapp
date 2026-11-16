import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../models/food_scan_result.dart';
import '../../core/errors/ai_quota_exceeded_exception.dart';
import '../../services/gemini_vision_service.dart';
import '../../widgets/ui/ui.dart';
import 'analysis_results_screen.dart';
import '../../core/utils/entitlement_gate.dart';

/// Natural-language logging: the user describes a meal, Gemini parses it into
/// discrete items, and the confirmed list moves on to the analysis review.
class AiLogScreen extends ConsumerStatefulWidget {
  const AiLogScreen({super.key, this.mealType = 'snack'});

  final String mealType;

  @override
  ConsumerState<AiLogScreen> createState() => _AiLogScreenState();
}

class _AiLogScreenState extends ConsumerState<AiLogScreen> {
  final _input = TextEditingController();
  final _vision = GeminiVisionService();

  bool _analyzing = false;
  FoodScanResult? _result;
  String? _error;

  static const _examples = [
    '2 rotis with dal and a bowl of curd',
    'Greek salad with hummus and pita',
    '150g grilled chicken, 1 cup rice, salad',
  ];

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final text = _input.text.trim();
    if (text.isEmpty || _analyzing) return;
    // Free for the first three days, then premium. See requireEntitlement:
    // it shows the paywall itself and returns true if the user subscribes on
    // the spot, so this tap completes rather than needing to be repeated.
    if (!await requireEntitlement(context, ref)) return;

    setState(() {
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
          _error = "I couldn't recognise any food in that description. "
              'Try naming the dish and a rough quantity.';
        }
      });
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

  void _review() {
    final result = _result;
    if (result == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalysisResultsScreen(
          result: result,
          mealType:
              result.mealType.isNotEmpty ? result.mealType : widget.mealType,
          sourceLabel: 'AI parsed',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAnalyze = _input.text.trim().isNotEmpty && !_analyzing;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: const TerraAppBar(
          title: 'Log with AI', titleColor: AppColors.primary),
      body: DismissKeyboard(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          // `resizeToAvoidBottomInset` already accounts for the keyboard; adding
          // viewInsets again double-counted it and rebuilt this whole screen on
          // every frame of the keyboard animation, dropping the text area's
          // focus as it was gaining it.
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.md, AppSpacing.page, 120),
          children: [
            Center(
              child: Column(
                children: [
                  Text('Describe your meal naturally.',
                      textAlign: TextAlign.center,
                      style: AppText.body(color: AppColors.onSurfaceVariant)
                          .copyWith(fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('"I had a Greek salad and some hummus…"',
                      textAlign: TextAlign.center,
                      style: AppText.bodySm(color: AppColors.secondary)
                          .copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TerraTextArea(
              controller: _input,
              hint: 'Tap here and describe your meal…',
              minLines: 4,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _examples
                  .map((e) => MiniPill(
                        label: e,
                        icon: Icons.bolt_rounded,
                        onTap: () {
                          _input.text = e;
                          _input.selection = TextSelection.collapsed(
                              offset: _input.text.length);
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            PillButton(
              label: _analyzing ? 'Analyzing…' : 'Analyze meal',
              icon: Icons.auto_awesome_rounded,
              loading: _analyzing,
              onPressed: canAnalyze ? _analyze : null,
            ),
            const SizedBox(height: AppSpacing.md),
            if (_error != null)
              TerraEmptyState(
                icon: Icons.no_food_rounded,
                title: 'Nothing detected',
                message: _error,
                accent: AppColors.error,
              ),
            if (_result != null) _detected(_result!),
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
          'Detected items',
          trailing: TerraBadge(
            label: 'AI active',
            icon: Icons.auto_awesome_rounded,
            color: AppColors.primary,
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
        const SizedBox(height: AppSpacing.xs),
        TerraCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          elevated: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Estimated total', style: AppText.bodyBold()),
              Text('${r.totalCalories} kcal',
                  style: AppText.data(color: AppColors.primary)),
            ],
          ),
        ),
      ],
    );
  }
}
