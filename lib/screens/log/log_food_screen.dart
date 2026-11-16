import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../models/meal.dart';
import '../../models/meal_slot.dart';
import '../../providers/meal_schedule_provider.dart';
import '../../services/meal_schedule_service.dart';
import '../../providers/daily_log_provider.dart';
import '../../core/utils/entitlement_gate.dart';
import '../../services/plan_limits.dart';
import '../../services/routine_logger.dart';
import '../../services/routine_service.dart';
import '../../services/subscription_service.dart';
import 'routine_sheets.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';

/// Whether a suggested food's quantity is tracked by piece count (eggs,
/// chapati) or by weight (rice, biryani) — decides which stepper the
/// quantity sheet shows and how macros get scaled.
enum _FoodUnit { piece, grams }

/// A quick-add food. Macro fields are per **one** [unit] — one piece for
/// [_FoodUnit.piece], or per 100g for [_FoodUnit.grams] — so the quantity
/// sheet can scale them live as the user adjusts the amount.
typedef _Suggestion = ({
  String name,
  _FoodUnit unit,
  String unitLabel,
  num defaultQty,
  num step,
  num minQty,
  num maxQty,
  double kcal,
  double p,
  double c,
  double f,
  double fb,
});

/// Entry point for logging: pick the meal slot, then choose how — search a
/// common food, describe it to the AI, reuse a saved routine, or open the
/// camera.
class LogFoodScreen extends ConsumerStatefulWidget {
  const LogFoodScreen({super.key, this.initialMealType});

  final String? initialMealType;

  @override
  ConsumerState<LogFoodScreen> createState() => _LogFoodScreenState();
}

class _LogFoodScreenState extends ConsumerState<LogFoodScreen> {
  /// Lightweight offline table so search works without a round trip. Icons are
  /// derived from the name by [FoodIconResolver], same as every other log path.
  ///
  /// Macros are per one [_Suggestion.unit] — one piece for [_FoodUnit.piece],
  /// or per 100g for [_FoodUnit.grams] — never a baked-in serving total, so
  /// the quantity sheet can scale any of these up or down before logging.
  static const _suggestions = <_Suggestion>[
    // India — piece-based
    (
      name: 'Boiled Egg',
      unit: _FoodUnit.piece,
      unitLabel: 'egg',
      defaultQty: 2,
      step: 1,
      minQty: 1,
      maxQty: 12,
      kcal: 78,
      p: 6,
      c: 0.6,
      f: 5,
      fb: 0
    ),
    (
      name: 'Chapati (Roti)',
      unit: _FoodUnit.piece,
      unitLabel: 'roti',
      defaultQty: 2,
      step: 1,
      minQty: 1,
      maxQty: 10,
      kcal: 90,
      p: 2.7,
      c: 17,
      f: 1.5,
      fb: 2
    ),
    (
      name: 'Idli',
      unit: _FoodUnit.piece,
      unitLabel: 'idli',
      defaultQty: 3,
      step: 1,
      minQty: 1,
      maxQty: 10,
      kcal: 39,
      p: 1.8,
      c: 7.9,
      f: 0.1,
      fb: 0.5
    ),
    (
      name: 'Dosa (Plain)',
      unit: _FoodUnit.piece,
      unitLabel: 'dosa',
      defaultQty: 1,
      step: 1,
      minQty: 1,
      maxQty: 5,
      kcal: 133,
      p: 3.9,
      c: 21,
      f: 3.7,
      fb: 1
    ),
    (
      name: 'Aloo Paratha',
      unit: _FoodUnit.piece,
      unitLabel: 'paratha',
      defaultQty: 1,
      step: 1,
      minQty: 1,
      maxQty: 5,
      kcal: 210,
      p: 4.5,
      c: 27,
      f: 9,
      fb: 2.5
    ),
    (
      name: 'Vada Pav',
      unit: _FoodUnit.piece,
      unitLabel: 'pav',
      defaultQty: 1,
      step: 1,
      minQty: 1,
      maxQty: 5,
      kcal: 286,
      p: 6,
      c: 40,
      f: 12,
      fb: 2
    ),
    (
      name: 'Dal (Katori)',
      unit: _FoodUnit.piece,
      unitLabel: 'katori',
      defaultQty: 1,
      step: 1,
      minQty: 1,
      maxQty: 4,
      kcal: 145,
      p: 9.5,
      c: 25,
      f: 0.5,
      fb: 6
    ),
    (
      name: 'Banana',
      unit: _FoodUnit.piece,
      unitLabel: 'banana',
      defaultQty: 1,
      step: 1,
      minQty: 1,
      maxQty: 5,
      kcal: 105,
      p: 1.3,
      c: 27,
      f: 0.4,
      fb: 3
    ),
    // Global — piece-based
    (
      name: 'Grilled Chicken Sandwich',
      unit: _FoodUnit.piece,
      unitLabel: 'sandwich',
      defaultQty: 1,
      step: 1,
      minQty: 1,
      maxQty: 4,
      kcal: 350,
      p: 28,
      c: 34,
      f: 11,
      fb: 2
    ),
    (
      name: 'Turkey Sandwich',
      unit: _FoodUnit.piece,
      unitLabel: 'sandwich',
      defaultQty: 1,
      step: 1,
      minQty: 1,
      maxQty: 4,
      kcal: 320,
      p: 24,
      c: 34,
      f: 9,
      fb: 3
    ),
    (
      name: 'Avocado Toast',
      unit: _FoodUnit.piece,
      unitLabel: 'slice',
      defaultQty: 1,
      step: 1,
      minQty: 1,
      maxQty: 4,
      kcal: 190,
      p: 4,
      c: 18,
      f: 12,
      fb: 5
    ),
    (
      name: 'Pancake',
      unit: _FoodUnit.piece,
      unitLabel: 'pancake',
      defaultQty: 3,
      step: 1,
      minQty: 1,
      maxQty: 8,
      kcal: 90,
      p: 2.5,
      c: 12,
      f: 3.5,
      fb: 0.5
    ),
    // India — gram-based (per 100g)
    (
      name: 'Chicken Biryani',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 250,
      step: 25,
      minQty: 25,
      maxQty: 500,
      kcal: 165,
      p: 9,
      c: 20,
      f: 5,
      fb: 1
    ),
    (
      name: 'Plain Rice',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 150,
      step: 25,
      minQty: 25,
      maxQty: 500,
      kcal: 130,
      p: 2.7,
      c: 28,
      f: 0.3,
      fb: 0.4
    ),
    (
      name: 'Paneer Bhurji',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 100,
      step: 25,
      minQty: 25,
      maxQty: 400,
      kcal: 265,
      p: 15,
      c: 5,
      f: 21,
      fb: 1
    ),
    (
      name: 'Chana Masala',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 150,
      step: 25,
      minQty: 25,
      maxQty: 400,
      kcal: 130,
      p: 7,
      c: 18,
      f: 4,
      fb: 5
    ),
    (
      name: 'Rajma Curry',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 150,
      step: 25,
      minQty: 25,
      maxQty: 400,
      kcal: 120,
      p: 7,
      c: 16,
      f: 3,
      fb: 6
    ),
    (
      name: 'Sprouts Salad',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 150,
      step: 25,
      minQty: 25,
      maxQty: 400,
      kcal: 30,
      p: 3,
      c: 4,
      f: 0.2,
      fb: 3
    ),
    (
      name: 'Curd (Plain)',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 150,
      step: 25,
      minQty: 25,
      maxQty: 400,
      kcal: 60,
      p: 3.5,
      c: 4.7,
      f: 3.3,
      fb: 0
    ),
    (
      name: 'Masala Oats',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 200,
      step: 25,
      minQty: 25,
      maxQty: 400,
      kcal: 70,
      p: 3,
      c: 12,
      f: 1.5,
      fb: 2
    ),
    // Global — gram-based (per 100g)
    (
      name: 'Chicken Breast (Grilled)',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 150,
      step: 25,
      minQty: 25,
      maxQty: 400,
      kcal: 165,
      p: 31,
      c: 0,
      f: 3.6,
      fb: 0
    ),
    (
      name: 'Greek Yogurt with Berries',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 200,
      step: 25,
      minQty: 25,
      maxQty: 400,
      kcal: 90,
      p: 7.5,
      c: 11,
      f: 1.5,
      fb: 1
    ),
    (
      name: 'Oatmeal with Banana',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 200,
      step: 25,
      minQty: 25,
      maxQty: 400,
      kcal: 85,
      p: 3,
      c: 15,
      f: 1.8,
      fb: 2
    ),
    (
      name: 'Caesar Salad with Chicken',
      unit: _FoodUnit.grams,
      unitLabel: 'g',
      defaultQty: 250,
      step: 25,
      minQty: 25,
      maxQty: 500,
      kcal: 110,
      p: 9,
      c: 4,
      f: 6.5,
      fb: 1.5
    ),
  ];

  final _search = TextEditingController();
  late String _mealType = widget.initialMealType ?? '';

  /// Options come from the shared schedule, so a renamed or added slot shows
  /// up here without this screen knowing anything about reminders.
  List<MealTypeOption> _options(List<MealSlot> slots) => [
        for (final slot in slots)
          MealTypeOption(
            value: slot.key,
            label: slot.label,
            icon: MealSlotStyle.icon(slot.key, label: slot.label),
          ),
      ];
  List<SavedRoutine> _routines = const [];

  /// Free photo scans left today, or null when it does not apply — the plan
  /// split is off, the user is on Pro, or it has not loaded yet.
  int? _freeScansLeft;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    // Preselect from the user's own schedule rather than fixed clock hours —
    // someone whose dinner reminder is 21:30 should not land on "snack". The
    // provider is seeded synchronously, so this needs no loading state.
    if (_mealType.isEmpty) {
      _mealType = MealScheduleService.currentKey(
          ref.read(mealScheduleProvider), DateTime.now());
    }
    final uid = SupabaseService.currentUserId;
    if (uid != null) {
      RoutineService.loadAll(uid).then((r) {
        if (mounted) setState(() => _routines = r);
      });
    }
    _loadFreeScans();
  }

  Future<void> _loadFreeScans() async {
    if (!kEnforcePremium) return;
    if (await SubscriptionService.instance.isEntitled()) return;
    final left = await PlanLimits.freeScansLeft();
    if (mounted) setState(() => _freeScansLeft = left);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Multiplies a suggestion's per-unit macros by [qty] — `qty / 100` for
  /// gram-based foods (macros are stored per 100g), `qty` directly for
  /// piece-based ones.
  ({int kcal, double p, double c, double f, double fb}) _scaled(
      _Suggestion s, num qty) {
    final mult = s.unit == _FoodUnit.grams ? qty / 100 : qty;
    return (
      kcal: (s.kcal * mult).round(),
      p: s.p * mult,
      c: s.c * mult,
      f: s.f * mult,
      fb: s.fb * mult,
    );
  }

  String _qtyLabel(_Suggestion s, num qty) => s.unit == _FoodUnit.grams
      ? '${qty.toInt()} g'
      : '${qty.toInt()} ${s.unitLabel}${qty == 1 ? '' : 's'}';

  /// Lets the user pick how many pieces/grams before it's logged, so
  /// "Boiled Egg" can become 3 eggs or "Chicken Biryani" can become 300g
  /// instead of always logging one fixed serving.
  Future<void> _openQuantitySheet(_Suggestion s) async {
    final qty = await showModalBottomSheet<num>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _QuantitySheet(
        suggestion: s,
        mealLabel: MealScheduleService.labelFor(
            ref.read(mealScheduleProvider), _mealType),
      ),
    );
    if (qty != null) await _logSuggestion(s, qty);
  }

  Future<void> _logSuggestion(_Suggestion s, num qty) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    final macros = _scaled(s, qty);
    try {
      await MealService.addMeal(
        ref,
        Meal(
          userId: uid,
          date: AppDateUtils.toDateOnly(DateTime.now()),
          mealType: _mealType,
          foodName: '${s.name} (${_qtyLabel(s, qty)})',
          calories: macros.kcal,
          proteinG: macros.p,
          carbsG: macros.c,
          fatG: macros.f,
          fiberG: macros.fb,
          logMethod: 'search',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${s.name} added to '
              '${MealScheduleService.labelFor(ref.read(mealScheduleProvider), _mealType)}.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save ${s.name} — try again.")),
      );
    }
  }

  /// Logs a saved meal. One tap logs a single portion; [portions] comes from
  /// the portion sheet when the user wants half, or two.
  Future<void> _logRoutine(SavedRoutine r, {double portions = 1}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    try {
      final kcal = await RoutineLogger.log(
        ref,
        uid: uid,
        routine: r,
        mealType: _mealType,
        portions: portions,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${r.name} logged — $kcal kcal.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't log ${r.name} — try again.")),
      );
    }
  }

  Future<void> _logRoutineByPortion(SavedRoutine r) async {
    final portions = await showPortionSheet(
      context,
      routine: r,
      mealLabel: MealScheduleService.labelFor(
          ref.read(mealScheduleProvider), _mealType),
    );
    if (portions != null) await _logRoutine(r, portions: portions);
  }

  Future<void> _addOwnDish() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    final saved = await showOwnDishSheet(context, uid: uid);
    if (saved == null || !mounted) return;
    setState(() => _routines = [saved, ..._routines]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${saved.name} saved to Quick Picks.')),
    );
  }

  /// "1 katori · 180 kcal" for a single dish, "3 items · 540 kcal" for a
  /// saved meal made of several.
  static String _routineSubtitle(SavedRoutine r) {
    if (r.items.length == 1) {
      final i = r.items.first;
      final qty = i.quantity == i.quantity.roundToDouble()
          ? i.quantity.toInt().toString()
          : i.quantity.toString();
      return '$qty ${i.unit} · ${r.totalCalories} kcal';
    }
    return '${r.items.length} items · ${r.totalCalories} kcal';
  }

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(mealScheduleProvider);
    final query = _search.text.trim().toLowerCase();
    final results = query.isEmpty
        ? _suggestions
        : _suggestions
            .where((s) => s.name.toLowerCase().contains(query))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TerraAppBar(
        title: 'Log Food',
        titleColor: AppColors.primary,
      ),
      resizeToAvoidBottomInset: true,
      body: DismissKeyboard(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          // `resizeToAvoidBottomInset` already lifts the body clear of the
          // keyboard; adding viewInsets here too double-counted it and rebuilt
          // the entire list on every keyboard-animation frame, which dropped
          // the search field's focus as it was gaining it.
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.lg),
          children: [
            Text('Which meal are we logging?', style: AppText.headlineLg()),
            const SizedBox(height: AppSpacing.sm),
            MealTypeSelector(
              options: _options(slots),
              selected: _mealType,
              onSelected: (t) => setState(() => _mealType = t),
            ),
            const SizedBox(height: AppSpacing.md),
            TerraField(
              controller: _search,
              hint: 'Search food items…',
              icon: Icons.search_rounded,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.search,
              suffix: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => _search.clear(),
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            _bigAction(
              title: 'Log with AI',
              subtitle: 'Describe your meal in plain words',
              icon: Icons.auto_awesome_rounded,
              color: AppColors.primary,
              onTap: () => context.push('/log-food/ai', extra: _mealType),
            ),
            const SizedBox(height: 12),
            _bigAction(
              title: 'Log by voice',
              subtitle: 'Just say what you ate — hands free',
              icon: Icons.mic_rounded,
              color: AppColors.secondary,
              onTap: () => context.push('/log-food/voice', extra: _mealType),
            ),
            const SizedBox(height: 12),
            _bigAction(
              title: 'Scan with camera',
              subtitle: _freeScansLeft == null
                  ? 'Point at your plate and let Proteinix estimate'
                  : _freeScansLeft == 0
                      ? "Today's ${PlanLimits.freeScansPerDay} free scans are "
                          'used — unlimited on Pro'
                      : '$_freeScansLeft of ${PlanLimits.freeScansPerDay} '
                          'free scans left today',
              icon: Icons.photo_camera_rounded,
              color: AppColors.tertiary,
              onTap: () async {
                await context.push('/scan', extra: _mealType);
                // A scan may just have been used.
                if (mounted) _loadFreeScans();
              },
            ),
            const SizedBox(height: 12),
            _bigAction(
              title: 'Scan barcode',
              subtitle: 'Packaged food, straight from the label — free',
              icon: Icons.qr_code_scanner_rounded,
              color: AppColors.secondary,
              onTap: () => context.push('/barcode', extra: _mealType),
            ),
            const SizedBox(height: AppSpacing.md),
            SectionHeading(
              'Quick Picks',
              actionLabel: 'Add your own dish',
              onAction: _addOwnDish,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_routines.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Dishes you save show up here, ready to log in one tap.',
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                ),
              )
            else
              ..._routines.take(6).map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TerraListRow(
                        title: r.name,
                        subtitle: _routineSubtitle(r),
                        icon: Icons.history_rounded,
                        iconColor: AppColors.primary,
                        // The row itself logs one portion in a single tap;
                        // this is the way in for half, or two.
                        trailing: MiniPill(
                          label: 'Portions',
                          background: AppColors.surfaceContainerHigh,
                          onTap: () => _logRoutineByPortion(r),
                        ),
                        onTap: () => _logRoutine(r),
                      ),
                    ),
                  ),
            const SizedBox(height: AppSpacing.md),
            SectionHeading(query.isEmpty ? 'Suggested Foods' : 'Results'),
            const SizedBox(height: AppSpacing.sm),
            if (results.isEmpty)
              TerraEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No match for "${_search.text.trim()}"',
                message: 'Try describing it to the AI instead.',
                action: SizedBox(
                  width: 220,
                  child: PillButton(
                    label: 'Log with AI',
                    icon: Icons.auto_awesome_rounded,
                    onPressed: () =>
                        context.push('/log-food/ai', extra: _mealType),
                  ),
                ),
              )
            else
              ...results.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TerraListRow(
                    title: s.name,
                    subtitle:
                        '${_scaled(s, s.defaultQty).kcal} kcal · ${_qtyLabel(s, s.defaultQty)}',
                    leading: FoodIcon(foodName: s.name, size: 48),
                    trailing: MiniPill(
                      label: 'Add',
                      background: AppColors.primary,
                      foreground: AppColors.onPrimary,
                      border: AppColors.primary,
                      onTap: () => _openQuantitySheet(s),
                    ),
                    onTap: () => _openQuantitySheet(s),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bigAction({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyBold()),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for picking how much of a suggested food to log — a
/// stepper in pieces (eggs, chapati) or grams (rice, biryani), with the
/// macro preview updating live so the user sees what they're about to add
/// before it's saved.
class _QuantitySheet extends StatefulWidget {
  const _QuantitySheet({required this.suggestion, required this.mealLabel});

  final _Suggestion suggestion;
  final String mealLabel;

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  late num _qty = widget.suggestion.defaultQty;

  void _adjust(num delta) {
    final s = widget.suggestion;
    setState(() => _qty = (_qty + delta).clamp(s.minQty, s.maxQty));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    final mult = s.unit == _FoodUnit.grams ? _qty / 100 : _qty;
    final kcal = (s.kcal * mult).round();
    final p = s.p * mult;
    final c = s.c * mult;
    final f = s.f * mult;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.page, AppSpacing.sm, AppSpacing.page, AppSpacing.lg),
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(s.name, style: AppText.headlineMd()),
            const SizedBox(height: 2),
            Text('Adding to ${widget.mealLabel}',
                style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  s.unit == _FoodUnit.grams ? 'QUANTITY (GRAMS)' : 'QUANTITY',
                  style: AppText.labelCaps(),
                ),
                Row(
                  children: [
                    _StepButton(
                        icon: Icons.remove_rounded,
                        onTap: () => _adjust(-s.step)),
                    SizedBox(
                      width: 88,
                      child: Column(
                        children: [
                          Text('${_qty.toInt()}', style: AppText.data()),
                          Text(
                            s.unit == _FoodUnit.grams
                                ? 'g'
                                : '${s.unitLabel}${_qty == 1 ? '' : 's'}',
                            style: AppText.bodySm(
                                color: AppColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    _StepButton(
                        icon: Icons.add_rounded, onTap: () => _adjust(s.step)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: AppRadius.lgR,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MacroStat(label: 'KCAL', value: '$kcal'),
                  _MacroStat(
                      label: 'PROTEIN', value: '${p.toStringAsFixed(0)}g'),
                  _MacroStat(label: 'CARBS', value: '${c.toStringAsFixed(0)}g'),
                  _MacroStat(label: 'FAT', value: '${f.toStringAsFixed(0)}g'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PillButton(
              label: 'Add to ${widget.mealLabel}',
              onPressed: () => Navigator.pop(context, _qty),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outline),
        ),
        child: Icon(icon, size: 18, color: AppColors.onSurface),
      ),
    );
  }
}

class _MacroStat extends StatelessWidget {
  const _MacroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppText.bodyBold()),
        const SizedBox(height: 2),
        Text(label, style: AppText.labelCaps(size: 9)),
      ],
    );
  }
}
