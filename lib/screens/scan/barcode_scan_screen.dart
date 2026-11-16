import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/date_utils.dart';
import '../../models/meal.dart';
import '../../providers/daily_log_provider.dart';
import '../../providers/meal_schedule_provider.dart';
import '../../services/meal_schedule_service.dart';
import '../../services/open_food_facts_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/ui/ui.dart';

/// Scan the barcode on packaged food and log it from the label values.
///
/// Free and unlimited on every plan: there is no AI call here, only a lookup
/// of the numbers printed on the pack, so nothing about it is metered or
/// gated. The figures are shown as exact, not "about", for the same reason.
class BarcodeScanScreen extends ConsumerStatefulWidget {
  const BarcodeScanScreen({super.key, this.mealType});

  final String? mealType;

  @override
  ConsumerState<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

enum _Stage { scanning, looking, notFound, failed }

class _BarcodeScanScreenState extends ConsumerState<BarcodeScanScreen> {
  final _scanner = MobileScannerController(
    // Retail product codes only — a QR code on the same pack is not a
    // product id and would just produce a "not found".
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  final _lookup = OpenFoodFactsService();

  _Stage _stage = _Stage.scanning;
  String? _lastCode;

  late final String _mealType = widget.mealType ??
      MealScheduleService.currentKey(
          ref.read(mealScheduleProvider), DateTime.now());

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    // The camera keeps reporting the same code many times a second; only the
    // first sighting while actually scanning starts a lookup.
    if (_stage != _Stage.scanning) return;
    String? code;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && OpenFoodFactsService.isProductBarcode(raw)) {
        code = raw;
        break;
      }
    }
    if (code == null) return;
    await _resolve(code);
  }

  Future<void> _resolve(String code) async {
    setState(() {
      _stage = _Stage.looking;
      _lastCode = code;
    });
    await _scanner.stop();
    HapticFeedback.selectionClick();

    try {
      final product = await _lookup.lookup(code);
      if (!mounted) return;
      if (product == null) {
        setState(() => _stage = _Stage.notFound);
        return;
      }
      final logged = await _openQuantitySheet(product);
      if (!mounted) return;
      if (logged) {
        Navigator.of(context).pop();
      } else {
        await _scanAgain();
      }
    } on BarcodeLookupException {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  Future<void> _scanAgain() async {
    setState(() => _stage = _Stage.scanning);
    await _scanner.start();
  }

  /// Returns true once the product has been logged.
  Future<bool> _openQuantitySheet(BarcodeProduct product) async {
    final qty = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BarcodeQuantitySheet(
        product: product,
        mealLabel: MealScheduleService.labelFor(
            ref.read(mealScheduleProvider), _mealType),
      ),
    );
    if (qty == null || !mounted) return false;

    final uid = SupabaseService.currentUserId;
    if (uid == null) return false;
    final m = product.forQuantity(qty);
    try {
      await MealService.addMeal(
        ref,
        Meal(
          userId: uid,
          date: AppDateUtils.toDateOnly(DateTime.now()),
          mealType: _mealType,
          foodName: product.displayName,
          quantity: qty,
          unit: product.unit,
          calories: m.kcal,
          proteinG: m.protein,
          carbsG: m.carbs,
          fatG: m.fat,
          fiberG: m.fiber,
          logMethod: 'barcode',
          // Label values, not an estimate.
          scanConfidence: 'high',
        ),
      );
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} logged — ${m.kcal} kcal.')),
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't save ${product.name} — try again.")),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TerraAppBar(title: 'Scan Barcode'),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.scanning || _Stage.looking => _camera(),
          _Stage.notFound => _message(
              icon: Icons.search_off_rounded,
              title: 'Not in the database yet',
              message: 'No nutrition values on record for '
                  '${_lastCode ?? 'this barcode'}. Search for it by name, or '
                  'describe it to the AI instead.',
            ),
          _Stage.failed => _message(
              icon: Icons.cloud_off_rounded,
              title: "Couldn't look that up",
              message: 'Check your connection and try again.',
              retryCode: _lastCode,
            ),
        },
      ),
    );
  }

  Widget _camera() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: ClipRRect(
              borderRadius: AppRadius.xlR,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _scanner,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => TerraEmptyState(
                      icon: Icons.no_photography_rounded,
                      title: 'Camera unavailable',
                      message: error.errorCode ==
                              MobileScannerErrorCode.permissionDenied
                          ? 'Allow camera access in Settings to scan barcodes.'
                          : 'The camera could not be started. Close other '
                              'camera apps and try again.',
                      accent: AppColors.error,
                    ),
                  ),
                  // A plain guide box. Detection runs on the whole frame, so
                  // this only tells the user where to aim.
                  Center(
                    child: Container(
                      width: 260,
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.lgR,
                        border: Border.all(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                  if (_stage == _Stage.looking)
                    const ColoredBox(
                      color: Color(0x99000000),
                      child: Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.page, 0, AppSpacing.page, AppSpacing.md),
          child: Text(
            _stage == _Stage.looking
                ? 'Looking up $_lastCode…'
                : 'Hold the barcode inside the box. Works for packaged food '
                    'and drinks.',
            textAlign: TextAlign.center,
            style: AppText.body(color: AppColors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String message,
    String? retryCode,
  }) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TerraEmptyState(icon: icon, title: title, message: message),
          const SizedBox(height: AppSpacing.md),
          if (retryCode != null) ...[
            PillButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: () => _resolve(retryCode),
            ),
            const SizedBox(height: 12),
          ],
          PillButton(
            label: 'Scan another barcode',
            tone: PillTone.outline,
            glow: false,
            icon: Icons.qr_code_scanner_rounded,
            onPressed: _scanAgain,
          ),
        ],
      ),
    );
  }
}

/// How much of the scanned product was eaten, in grams or millilitres.
class _BarcodeQuantitySheet extends StatefulWidget {
  const _BarcodeQuantitySheet({required this.product, required this.mealLabel});

  final BarcodeProduct product;
  final String mealLabel;

  @override
  State<_BarcodeQuantitySheet> createState() => _BarcodeQuantitySheetState();
}

class _BarcodeQuantitySheetState extends State<_BarcodeQuantitySheet> {
  late final _qty = TextEditingController(
      text: (widget.product.servingSize ?? 100).round().toString());

  @override
  void initState() {
    super.initState();
    _qty.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  double? get _value {
    final v = double.tryParse(_qty.text.trim());
    return (v == null || v <= 0 || v > 5000) ? null : v;
  }

  void _set(double v) => _qty.text = v.round().toString();

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final value = _value;
    final m = p.forQuantity(value ?? 0);
    final serving = p.servingSize;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.page,
        right: AppSpacing.page,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            AppSpacing.md,
      ),
      child: TerraCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.name, style: AppText.headlineMd()),
            if (p.brand != null && p.brand!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(p.brand!,
                  style: AppText.bodySm(color: AppColors.onSurfaceVariant)),
            ],
            const SizedBox(height: 4),
            Text(
              'From the label: ${p.kcalPer100.round()} kcal per 100 ${p.unit}',
              style: AppText.bodySm(color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            TerraField(
              controller: _qty,
              label: 'How much did you have?',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              trailingText: p.unit,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (serving != null)
                  MiniPill(
                    label: '1 serving · ${serving.round()} ${p.unit}',
                    background: AppColors.surfaceContainer,
                    onTap: () => _set(serving),
                  ),
                if (serving != null)
                  MiniPill(
                    label: '2 servings',
                    background: AppColors.surfaceContainer,
                    onTap: () => _set(serving * 2),
                  ),
                MiniPill(
                  label: '100 ${p.unit}',
                  background: AppColors.surfaceContainer,
                  onTap: () => _set(100),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _macro('${m.kcal}', 'kcal'),
                _macro('${m.protein.toStringAsFixed(1)}g', 'protein'),
                _macro('${m.carbs.toStringAsFixed(1)}g', 'carbs'),
                _macro('${m.fat.toStringAsFixed(1)}g', 'fat'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            PillButton(
              label: 'Add to ${widget.mealLabel}',
              onPressed:
                  value == null ? null : () => Navigator.pop(context, value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _macro(String value, String label) => Column(
        children: [
          Text(value, style: AppText.bodyBold()),
          const SizedBox(height: 2),
          Text(label.toUpperCase(),
              style: AppText.labelCaps(color: AppColors.onSurfaceVariant)),
        ],
      );
}
