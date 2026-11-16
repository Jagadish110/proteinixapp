import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/technical_issue.dart';
import '../../models/daily_log.dart';
import '../../models/food_scan_result.dart';
import '../../models/meal.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/daily_log_provider.dart';
import '../../services/gemini_vision_service.dart';
import '../../services/routine_service.dart';
import '../../services/supabase_service.dart';
import '../../providers/meal_schedule_provider.dart';
import '../../services/meal_schedule_service.dart';
import '../../widgets/ui/ui.dart';

/// Shared review screen for both camera scans and AI text logging.
///
/// Shows the estimated energy, a macro breakdown and every detected item with
/// editable portions before anything is written to the log.
class AnalysisResultsScreen extends ConsumerStatefulWidget {
  const AnalysisResultsScreen({
    super.key,
    required this.result,
    required this.mealType,
    this.image,
    this.sourceLabel = 'AI verified',
  });

  final FoodScanResult result;
  final String mealType;
  final File? image;
  final String sourceLabel;

  @override
  ConsumerState<AnalysisResultsScreen> createState() =>
      _AnalysisResultsScreenState();
}

class _AnalysisResultsScreenState extends ConsumerState<AnalysisResultsScreen> {
  late final List<FoodItem> _items = List.of(widget.result.foodItems);
  late String _mealType = widget.mealType;
  bool _saving = false;

  final _vision = GeminiVisionService();

  int get _calories => _items.fold(0, (s, i) => s + i.calories);
  double get _protein => _items.fold(0.0, (s, i) => s + i.proteinG);
  double get _carbs => _items.fold(0.0, (s, i) => s + i.carbsG);
  double get _fat => _items.fold(0.0, (s, i) => s + i.fatG);
  double get _fiber => _items.fold(0.0, (s, i) => s + i.fiberG);
  double get _weight => _items.fold(0.0, (s, i) => s + i.quantity);

  Color get _confidenceColor => switch (widget.result.confidence) {
        'high' => AppColors.secondary,
        'low' => AppColors.error,
        _ => AppColors.primary,
      };

  Future<void> _log() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null || _items.isEmpty) return;
    setState(() => _saving = true);
    final date = AppDateUtils.toDateOnly(DateTime.now());
    try {
      for (final item in _items) {
        await MealService.addMeal(
          ref,
          Meal(
            userId: uid,
            date: date,
            mealType: _mealType,
            foodName: item.name,
            quantity: item.quantity,
            unit: item.unit,
            calories: item.calories,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            fiberG: item.fiberG,
            logMethod: widget.image != null ? 'scan' : 'ai_text',
            scanConfidence: widget.result.confidence,
          ),
        );
      }
      if (!mounted) return;
      // Resolved before the pop, not after: popUntil tears this screen's
      // context down as part of the same call, and looking the messenger up
      // again afterward means looking it up on a context mid-deactivation —
      // which is exactly the "deactivated widget" throw seen in Diagnostics.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      messenger.showSnackBar(
        SnackBar(content: Text('Logged $_calories kcal to $_mealType.')),
      );
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTechnicalIssueSnack(
        context,
        action: 'log that meal',
        reportContext: 'analysis_results_log_meal',
        error: e,
        stack: s,
      );
    }
  }

  Future<void> _saveRoutine() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _RoutineNameDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await RoutineService.create(
      uid: uid,
      name: name,
      items: _items.map(RoutineItem.fromFoodItem).toList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$name" saved to Quick Picks.')),
    );
  }

  /// Index currently being re-priced after a rename, or null.
  int? _renaming;

  /// Lets the user correct a misidentified dish, then re-prices it.
  ///
  /// The AI's runner-up guesses are offered as one-tap chips: models rank a
  /// short candidate list far more reliably than they commit to a single
  /// answer, so most corrections should be one tap rather than typing.
  Future<void> _editName(int index) async {
    final item = _items[index];
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(item: item),
    );
    final name = picked?.trim() ?? '';
    if (!mounted || name.isEmpty || name == item.name) return;

    setState(() => _renaming = index);

    // Re-price the corrected food at the portion already on screen. Keeping the
    // old macros under a new name would look right and be wrong.
    FoodItem? priced;
    try {
      final qty = item.quantity.toStringAsFixed(item.unit == 'kg' ? 2 : 0);
      final res = await _vision.scanText('$qty ${item.unit} $name');
      if (res.detected && res.foodItems.isNotEmpty)
        priced = res.foodItems.first;
    } catch (_) {
      // Offline or the call failed — fall through to a rename-only update.
    }

    if (!mounted) return;
    setState(() {
      _items[index] = item.renamedTo(name, source: priced);
      _renaming = null;
    });

    if (priced == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Renamed, but couldn't recalculate macros — check the numbers."),
        ),
      );
    }
  }

  Future<void> _editPortion(int index) async {
    final item = _items[index];
    final result = await showDialog<({double qty, String unit})>(
      context: context,
      builder: (_) => _PortionDialog(item: item),
    );
    if (result == null) return;
    setState(() =>
        _items[index] = item.copyWith(quantity: result.qty, unit: result.unit));
  }

  void _step(int index, bool up) {
    final item = _items[index];
    final step = item.unit == 'kg' ? 0.05 : 10.0;
    final min = item.unit == 'kg' ? 0.01 : 10.0;
    final next = up ? item.quantity + step : item.quantity - step;
    setState(() =>
        _items[index] = item.copyWith(quantity: next.clamp(min, 99999.0)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final today = AppDateUtils.toDateOnly(DateTime.now());
    final todayLog = ref.watch(dailyLogProvider(today));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TerraAppBar(title: 'Analysis Results'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.md, AppSpacing.page, 120),
        children: [
          if (widget.image != null) _hero(),
          const SizedBox(height: AppSpacing.md),
          Center(
              child:
                  Text('ESTIMATED ENERGY', style: AppText.labelCaps(size: 11))),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$_calories',
                  style: AppText.display(color: AppColors.primary)
                      .copyWith(fontSize: 64)),
              const SizedBox(width: 6),
              Text('kcal',
                  style: AppText.headlineLg(color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              widget.result.portionEstimationMethod.isNotEmpty
                  ? widget.result.portionEstimationMethod
                  : 'Based on the detected ingredients and typical portion sizes.',
              textAlign: TextAlign.center,
              style: AppText.body(color: AppColors.onSurfaceVariant)
                  .copyWith(height: 1.5),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _breakdownCard(),
          if (profile != null) _insightCard(profile, todayLog),
          const SizedBox(height: AppSpacing.gutter),
          const SectionLabel('Meal type'),
          const SizedBox(height: 10),
          SegmentedPill<String>(
            values: [for (final s in ref.watch(mealScheduleProvider)) s.key],
            selected: _mealType,
            labelBuilder: (t) =>
                MealScheduleService.labelFor(ref.read(mealScheduleProvider), t),
            activeColor: AppColors.primary,
            activeTextColor: AppColors.onPrimary,
            onChanged: (t) => setState(() => _mealType = t),
          ),
          const SizedBox(height: AppSpacing.md),
          const SectionHeading('Detected Items'),
          const SizedBox(height: AppSpacing.sm),
          ...List.generate(_items.length, (i) => _itemCard(i)),
          if (_items.isEmpty)
            const TerraEmptyState(
              icon: Icons.no_food_rounded,
              title: 'Nothing detected',
              message: 'Go back and try a clearer photo or description.',
              accent: AppColors.error,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, 0, AppSpacing.page, AppSpacing.sm),
          child: Row(
            children: [
              PillButton(
                label: 'Save routine',
                tone: PillTone.outline,
                icon: Icons.bookmark_add_outlined,
                glow: false,
                expand: false,
                onPressed: _items.isEmpty ? null : _saveRoutine,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PillButton(
                  label: 'Log meal',
                  icon: Icons.check_rounded,
                  loading: _saving,
                  onPressed: _items.isEmpty || _saving ? null : _log,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    return ClipRRect(
      borderRadius: AppRadius.cardR,
      child: Stack(
        children: [
          Image.file(widget.image!,
              height: 220, width: double.infinity, fit: BoxFit.cover),
          Positioned(
            top: 12,
            right: 12,
            child: TerraBadge(
              label: widget.sourceLabel,
              icon: Icons.verified_rounded,
              color: _confidenceColor,
              filled: true,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ESTIMATED PLATE WEIGHT',
                      style: AppText.labelCaps(size: 10)),
                  const SizedBox(height: 2),
                  Text('~ ${_weight.round()}g total',
                      style: AppText.headlineLg()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownCard() {
    return TerraCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Nutritional Breakdown', style: AppText.headlineMd()),
              Text(widget.result.confidence.toUpperCase(),
                  style: AppText.labelCaps(color: _confidenceColor, size: 11)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 12.0;
              final ring = ((c.maxWidth - gap * 3) / 4).clamp(44.0, 66.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child:
                          _macro('Protein', _protein, AppColors.protein, ring)),
                  const SizedBox(width: gap),
                  Expanded(
                      child: _macro('Carbs', _carbs, AppColors.carbs, ring)),
                  const SizedBox(width: gap),
                  Expanded(child: _macro('Fats', _fat, AppColors.fat, ring)),
                  const SizedBox(width: gap),
                  Expanded(
                      child: _macro('Fiber', _fiber, AppColors.fiber, ring)),
                ],
              );
            },
          ),
          if (widget.result.calorieCheck.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(widget.result.calorieCheck,
                textAlign: TextAlign.center, style: AppText.labelCaps(size: 9)),
          ],
        ],
      ),
    );
  }

  /// Folds this meal's macros into today's already-logged totals and shows
  /// what's left against the user's goals — computed instantly from local
  /// state, no API call, so it updates live as portions are edited above.
  Widget _insightCard(UserProfile profile, DailyLog? today) {
    final consumedCal = (today?.caloriesConsumed ?? 0) + _calories;
    final consumedProtein = (today?.proteinG ?? 0) + _protein;
    final consumedWater = today?.waterMl ?? 0;

    final String message;
    if (profile.calorieGoal > 0 && consumedCal > profile.calorieGoal) {
      final over = consumedCal - profile.calorieGoal;
      message = "This meal puts you $over kcal over today's budget. A "
          'lighter next meal or a short walk can help balance it out.';
    } else {
      final remCal =
          (profile.calorieGoal - consumedCal).clamp(0, profile.calorieGoal);
      final remProtein = (profile.proteinGoalG - consumedProtein)
          .clamp(0, profile.proteinGoalG);
      final remWater =
          (profile.waterGoalMl - consumedWater).clamp(0, profile.waterGoalMl);
      message = "After this meal you'll have $remCal kcal, "
          "${remProtein.round()}g protein and "
          '${(remWater / 1000).toStringAsFixed(1)}L water left for today.';
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.gutter),
      child: TerraCard(
        color: AppColors.secondary.withValues(alpha: 0.08),
        borderColor: AppColors.secondary.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: AppColors.secondary, size: 18),
                const SizedBox(width: 8),
                Text('AI INSIGHT',
                    style: AppText.labelCaps(
                        color: AppColors.secondary, size: 11)),
              ],
            ),
            const SizedBox(height: 8),
            Text(message, style: AppText.body().copyWith(height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _macro(String label, double grams, Color color, double size) {
    // Ring fill is relative to the largest macro so the group reads comparatively.
    final maxG = [_protein, _carbs, _fat, _fiber]
        .fold<double>(1, (m, v) => v > m ? v : m);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ProgressRing(
          value: grams / maxG,
          color: color,
          size: size,
          strokeWidth: 5,
          center: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${grams.round()}g',
                style: AppText.labelCaps(color: AppColors.onSurface, size: 10)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.labelCaps(size: 9),
        ),
      ],
    );
  }

  Widget _itemCard(int i) {
    final item = _items[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TerraCard(
        padding: const EdgeInsets.all(14),
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FoodIcon(foodName: item.name, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The name is editable. A misidentified dish makes every
                      // macro wrong regardless of portion, and this was
                      // previously display-only — there was no way to correct it.
                      GestureDetector(
                        onTap: _renaming == i ? null : () => _editName(i),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(item.name,
                                  style: AppText.bodyBold(),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 6),
                            if (_renaming == i)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              )
                            else
                              const Icon(Icons.edit_rounded,
                                  size: 12, color: AppColors.onSurfaceVariant),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _editPortion(i),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Text(
                              '${item.quantity.toStringAsFixed(item.unit == 'kg' ? 2 : 0)} ${item.unit}',
                              style: AppText.bodySm(color: AppColors.primary)
                                  .copyWith(
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_rounded,
                                size: 12, color: AppColors.primary),
                            if (item.cookingMethod.isNotEmpty)
                              Text(' · ${item.cookingMethod}',
                                  style: AppText.bodySm(
                                      color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Text('${item.calories} kcal', style: AppText.bodyBold()),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'P ${item.proteinG.toStringAsFixed(1)}g · '
                    'C ${item.carbsG.toStringAsFixed(1)}g · '
                    'F ${item.fatG.toStringAsFixed(1)}g · '
                    'Fb ${item.fiberG.toStringAsFixed(1)}g',
                    style: AppText.labelCaps(size: 10),
                  ),
                ),
                _stepper(Icons.remove_rounded, () => _step(i, false)),
                const SizedBox(width: 8),
                _stepper(Icons.add_rounded, () => _step(i, true)),
                const SizedBox(width: 8),
                _stepper(Icons.close_rounded,
                    () => setState(() => _items.removeAt(i)),
                    color: AppColors.error),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepper(IconData icon, VoidCallback onTap,
          {Color color = AppColors.onSurface}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.outline),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      );
}

/// Correct a misidentified dish.
///
/// The AI's runner-up guesses are shown as chips because a tap is far cheaper
/// than typing, and because "pick from these three" is the question the model
/// was actually good at answering.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.item});

  final FoodItem item;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _ctrl = TextEditingController(text: widget.item.name);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alts = widget.item.alternatives;
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: const Text('What is this dish?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: AppText.body(),
            decoration: const InputDecoration(hintText: 'e.g. Mutton Pulao'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          if (alts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('DID YOU MEAN', style: AppText.labelCaps(size: 10)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final alt in alts)
                  MiniPill(
                    label: alt,
                    foreground: AppColors.primary,
                    onTap: () => Navigator.pop(context, alt),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Macros are recalculated for the corrected dish.',
            style: AppText.bodySm(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// Name prompt for saving the current analysis as a reusable routine.
///
/// Owns its controller, and that is the entire point. Creating it in the caller
/// and disposing it after `await showDialog` looks correct but is not: the
/// future completes on `Navigator.pop`, while the dialog keeps rendering
/// through its exit animation. The still-mounted TextField then rebuilds
/// against a disposed controller, which throws "A TextEditingController was
/// used after being disposed" and takes the overlay down with it — duplicate
/// GlobalKeys and a `_dependents.isEmpty` assertion, several frames later and
/// nowhere near the real cause. A State disposes with the route, after the
/// animation, so the lifetimes actually match.
class _RoutineNameDialog extends StatefulWidget {
  const _RoutineNameDialog();

  @override
  State<_RoutineNameDialog> createState() => _RoutineNameDialogState();
}

class _RoutineNameDialogState extends State<_RoutineNameDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save as routine'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(hintText: 'e.g. My usual lunch'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Quantity and unit editor for one analysed item.
///
/// Same ownership rule as [_RoutineNameDialog], and it also replaces the
/// StatefulBuilder this used to need for the unit toggle — a real State does
/// both jobs.
class _PortionDialog extends StatefulWidget {
  const _PortionDialog({required this.item});

  final FoodItem item;

  @override
  State<_PortionDialog> createState() => _PortionDialogState();
}

class _PortionDialogState extends State<_PortionDialog> {
  late final _ctrl = TextEditingController(
      text: widget.item.quantity
          .toStringAsFixed(widget.item.unit == 'kg' ? 2 : 0));
  late String _unit = widget.item.unit;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v == null || v <= 0) return;
    Navigator.pop(context, (qty: v, unit: _unit));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item.name),
      content: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _apply(),
              style: AppText.data(),
            ),
          ),
          const SizedBox(width: 12),
          SegmentedPill<String>(
            values: const ['g', 'ml', 'kg'],
            selected: _unit,
            compact: true,
            labelBuilder: (u) => u,
            onChanged: (u) => setState(() => _unit = u),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(onPressed: _apply, child: const Text('Apply')),
      ],
    );
  }
}
