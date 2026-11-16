import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../services/routine_logger.dart';
import '../../services/routine_service.dart';
import '../../widgets/ui/ui.dart';

EdgeInsets _sheetInsets(BuildContext context) => EdgeInsets.only(
      left: AppSpacing.page,
      right: AppSpacing.page,
      bottom: MediaQuery.of(context).viewInsets.bottom +
          MediaQuery.of(context).padding.bottom +
          AppSpacing.md,
    );

/// Asks how many portions of [routine] to log. Returns the multiplier, or
/// null if the sheet was dismissed.
Future<double?> showPortionSheet(
  BuildContext context, {
  required SavedRoutine routine,
  required String mealLabel,
}) {
  return showModalBottomSheet<double>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PortionSheet(routine: routine, mealLabel: mealLabel),
  );
}

class _PortionSheet extends StatefulWidget {
  const _PortionSheet({required this.routine, required this.mealLabel});

  final SavedRoutine routine;
  final String mealLabel;

  @override
  State<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<_PortionSheet> {
  double _portions = 1;

  @override
  Widget build(BuildContext context) {
    final r = widget.routine;
    final kcal = RoutineLogger.caloriesFor(r, _portions);
    final protein = r.totalProtein * _portions;

    return Padding(
      padding: _sheetInsets(context),
      child: TerraCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(r.name, style: AppText.headlineMd()),
            const SizedBox(height: 2),
            Text('How many portions?',
                style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in RoutineLogger.portionChoices)
                  MiniPill(
                    label: RoutineLogger.portionLabel(p),
                    background: p == _portions
                        ? AppColors.primary
                        : AppColors.surfaceContainer,
                    foreground: p == _portions ? AppColors.onPrimary : null,
                    onTap: () => setState(() => _portions = p),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$kcal kcal · ${protein.toStringAsFixed(1)}g protein',
              style: AppText.bodyBold(),
            ),
            const SizedBox(height: AppSpacing.sm),
            PillButton(
              label: 'Add to ${widget.mealLabel}',
              onPressed: () => Navigator.pop(context, _portions),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user enter one of their own dishes once — a name and what a
/// single portion contains — and saves it alongside their other saved meals,
/// so from then on it is logged by portion in a tap.
///
/// Returns the saved dish, or null if the sheet was dismissed.
Future<SavedRoutine?> showOwnDishSheet(
  BuildContext context, {
  required String uid,
}) {
  return showModalBottomSheet<SavedRoutine>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _OwnDishSheet(uid: uid),
  );
}

class _OwnDishSheet extends StatefulWidget {
  const _OwnDishSheet({required this.uid});

  final String uid;

  @override
  State<_OwnDishSheet> createState() => _OwnDishSheetState();
}

class _OwnDishSheetState extends State<_OwnDishSheet> {
  final _name = TextEditingController();
  final _portion = TextEditingController(text: 'serving');
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  bool _saving = false;
  String? _error;

  static final _decimal = [
    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}(\.\d{0,1})?')),
  ];

  @override
  void dispose() {
    for (final c in [_name, _portion, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    final name = _name.text.trim();
    final kcal = _num(_kcal);
    if (name.isEmpty) {
      setState(() => _error = 'Give the dish a name.');
      return;
    }
    if (kcal <= 0) {
      setState(() => _error = 'Enter the calories in one portion.');
      return;
    }
    final unit =
        _portion.text.trim().isEmpty ? 'serving' : _portion.text.trim();

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await RoutineService.create(
        uid: widget.uid,
        name: name,
        items: [
          RoutineItem(
            name: name,
            quantity: 1,
            unit: unit,
            calories: kcal.round(),
            proteinG: _num(_protein),
            carbsG: _num(_carbs),
            fatG: _num(_fat),
            fiberG: 0,
          ),
        ],
      );
      if (mounted) Navigator.pop(context, saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save that dish — try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _sheetInsets(context),
      child: TerraCard(
        // The fields scroll; the error and the Save button do not. On a small
        // phone with large text and the keyboard up, a single scrolling
        // column pushed the button below the fold with nothing to say it was
        // there.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add your own dish', style: AppText.headlineMd()),
                    const SizedBox(height: 2),
                    Text(
                      'Enter it once. After that it is one tap to log, by portion.',
                      style: AppText.bodySm(color: AppColors.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TerraField(
                      controller: _name,
                      label: 'Dish name',
                      hint: "e.g. Mum's rajma",
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TerraField(
                      controller: _portion,
                      label: 'One portion is a…',
                      hint: 'katori, plate, piece, cup',
                      textCapitalization: TextCapitalization.none,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TerraField(
                            controller: _kcal,
                            label: 'Calories',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            trailingText: 'kcal',
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TerraField(
                            controller: _protein,
                            label: 'Protein',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: _decimal,
                            trailingText: 'g',
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TerraField(
                            controller: _carbs,
                            label: 'Carbs',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: _decimal,
                            trailingText: 'g',
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TerraField(
                            controller: _fat,
                            label: 'Fat',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: _decimal,
                            trailingText: 'g',
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppText.bodySm(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.sm),
            PillButton(
              label: 'Save dish',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
