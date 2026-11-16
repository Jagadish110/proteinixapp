import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/meal_schedule_provider.dart';
import '../../services/error_reporter.dart';
import '../../services/meal_schedule_service.dart';
import '../../widgets/ui/ui.dart';
import '../log/meal_analysis_screen.dart';

class FoodScannerScreen extends ConsumerStatefulWidget {
  const FoodScannerScreen({super.key, this.mealType});

  final String? mealType;

  @override
  ConsumerState<FoodScannerScreen> createState() => _ScannerState();
}

class _ScannerState extends ConsumerState<FoodScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cam;
  late String _mealType = widget.mealType ?? _defaultMealType();
  bool _busy = false;
  bool _permissionDenied = false;
  bool _torch = false;

  /// Guards against two `initialize()` calls overlapping. The camera plugin
  /// throws IllegalStateException / a null-check error if a second controller
  /// starts before the first one's surface producer is ready.
  bool _initializing = false;
  String? _cameraError;

  static String _defaultMealType() {
    final h = DateTime.now().hour;
    if (h < 11) return 'breakfast';
    if (h < 16) return 'lunch';
    if (h < 19) return 'snack';
    return 'dinner';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Held locally because `mounted` is already false by the time this runs.
    final cam = _cam;
    _cam = null;
    if (_torch) {
      // Fire-and-forget: dispose() cannot await. The dispose below releases the
      // lamp on its own on every stack we've seen, so this is belt-and-braces
      // for the ones that don't — and it must not throw here if the controller
      // wins the race.
      _torch = false;
      cam?.setFlashMode(FlashMode.off).catchError((Object _) {});
    }
    cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` fires for transient interruptions (permission dialogs, the
    // notification shade), so tearing the camera down there causes a
    // dispose/reinit storm. Only release it on a real background transition.
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _releaseCamera();
      case AppLifecycleState.resumed:
        if (_cam == null && !_initializing) _initCamera();
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _releaseCamera() async {
    final cam = _cam;
    if (cam == null) return;
    // Drop the reference before disposing so no frame can build a preview
    // against a disposed controller.
    if (mounted) {
      setState(() => _cam = null);
    } else {
      _cam = null;
    }

    final wasLit = _torch;
    _torch = false;
    try {
      // Explicit, before the dispose that would usually imply it. Closing the
      // capture session releases the lamp on most stacks, but not all of them,
      // and a torch left burning after the app is backgrounded is the one
      // failure here the user cannot see the cause of.
      if (wasLit) await cam.setFlashMode(FlashMode.off);
    } catch (_) {}
    try {
      await cam.dispose();
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    if (mounted) setState(() => _cameraError = null);

    try {
      // Never stack controllers — release any existing one first.
      await _releaseCamera();

      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'No camera found on this device.');
        }
        return;
      }

      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      // veryHigh (1080p), not medium (720x480).
      //
      // Gemini reads images as 768x768 tiles, so a 480p capture arrives as a
      // single upscaled tile with the texture cues that distinguish foods —
      // grain, sheen, char, garnish — already destroyed. It also made camera
      // scans systematically worse than gallery picks, which come in at full
      // resolution, so the same dish scored differently depending on how it
      // was supplied.
      final ctl = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await ctl.initialize();

      if (!mounted) {
        await ctl.dispose();
        return;
      }
      setState(() {
        _cam = ctl;
        _permissionDenied = false;
        _cameraError = null;
      });
    } on CameraException catch (e, s) {
      if (!mounted) return;
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutShowUI') {
        setState(() => _permissionDenied = true);
      } else {
        // The driver's own message ("Failed to acquire the camera device")
        // reads as a fault the user caused; the code goes to error_logs.
        ErrorReporter.report('camera_init', e, s);
        setState(() => _cameraError =
            "The camera couldn't start. Close any other app using it "
                'and try again.');
      }
    } catch (e, s) {
      ErrorReporter.report('camera_init', e, s);
      if (mounted) {
        setState(() => _cameraError =
            "The camera couldn't start on this device. You can still log "
                'a meal by description or by voice.');
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _toggleTorch() async {
    if (_torch) return _torchOff();

    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.setFlashMode(FlashMode.torch);
      if (mounted) setState(() => _torch = true);
    } catch (_) {}
  }

  /// Puts the torch out. A no-op when it is already off.
  ///
  /// [FlashMode.torch] is a *continuous* lamp, not a shutter flash — nothing
  /// turns it off on its own. Leaving the screen with it lit means walking
  /// around with the LED burning until something else claims the camera, which
  /// is both alarming and a real drain on the battery.
  Future<void> _torchOff() async {
    if (!_torch) return;
    final cam = _cam;
    // Flipped before the await so the button stops reading "on" immediately,
    // and so a second call cannot start a competing platform request.
    if (mounted) {
      setState(() => _torch = false);
    } else {
      _torch = false;
    }
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.setFlashMode(FlashMode.off);
    } catch (_) {}
  }

  Future<void> _capture() async {
    final cam = _cam;
    if (cam == null || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await cam.takePicture();
      // The shot is taken, so the lamp has done its job. Left on, it stayed lit
      // through the analysis screen and was still burning when the user came
      // back — the torch is a per-shot tool, not a mode.
      await _torchOff();
      // Some OEM camera stacks freeze the preview after a capture.
      try {
        await cam.resumePreview();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _busy = false);
      _openAnalysis(File(shot.path));
    } catch (e) {
      // Same reasoning on the failure path: a capture that threw should not
      // leave the lamp on either.
      await _torchOff();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    // The gallery has no use for a torch, and on OEMs that don't background the
    // app for the picker nothing else would turn it off.
    await _torchOff();
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;
    _openAnalysis(File(picked.path));
  }

  void _openAnalysis(File file) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealAnalysisScreen(image: file, mealType: _mealType),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Recognition runs on Gemini, so there's nothing useful to do with a photo
    // offline — better to say so up front than let the user shoot a meal and
    // fail at the analysis step. Manual logging stays available.
    if (!ref.watch(isOnlineProvider)) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        appBar: TerraAppBar(title: 'Log with Camera'),
        body: OfflineAIWidget(featureName: 'AI Food Scanner'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  CircleIconButton(
                    icon: Icons.arrow_back_rounded,
                    background: AppColors.surfaceContainer,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Text('Log with Camera',
                        textAlign: TextAlign.center,
                        style: AppText.headlineMd()),
                  ),
                  CircleIconButton(
                    icon: Icons.tips_and_updates_outlined,
                    background: AppColors.surfaceContainer,
                    onTap: _showTips,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          Expanded(child: _viewfinder()),
          _controls(),
        ],
      ),
    );
  }

  Widget _viewfinder() {
    if (_permissionDenied) return _permissionState();
    if (_cameraError != null) return _errorState();

    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    final preview = cam.value.previewSize;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fall back to the plugin's own sizing when previewSize isn't reported.
        if (preview == null)
          CameraPreview(cam)
        else
          // `clipBehavior` is load-bearing, not tidiness. BoxFit.cover scales
          // the preview until it fills the slot, which by definition leaves it
          // overflowing on one axis — and FittedBox defaults to Clip.none, so
          // that overflow paints straight outside its own bounds.
          //
          // The enclosing Stack does not save us: it only clips when a
          // *positioned* child overflows, and this one reports the slot's exact
          // size while painting well beyond it. A 9:16 preview in this slot
          // spilled ~55px above, which landed squarely on the header row and
          // sliced the back button and title in half.
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: preview.height,
              height: preview.width,
              child: CameraPreview(cam),
            ),
          ),
        const ScanFrame(),
        Align(
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.35),
              borderRadius: AppRadius.pill,
            ),
            child: SegmentedPill<String>(
              values: [for (final s in ref.watch(mealScheduleProvider)) s.key],
              selected: _mealType,
              activeColor: AppColors.primary,
              activeTextColor: AppColors.onPrimary,
              labelBuilder: (t) => MealScheduleService.labelFor(
                  ref.read(mealScheduleProvider), t),
              onChanged: (t) => setState(() => _mealType = t),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorState() {
    return TerraEmptyState(
      icon: Icons.videocam_off_rounded,
      title: 'Camera could not start',
      message: 'You can still pick a photo from your gallery — the AI analyses '
          'it exactly the same way.',
      accent: AppColors.error,
      action: Column(
        children: [
          SizedBox(
            width: 240,
            child: PillButton(
              label: 'Pick from gallery',
              icon: Icons.photo_library_rounded,
              onPressed: _import,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _initCamera,
            child: const Text('Try camera again'),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              _cameraError ?? '',
              textAlign: TextAlign.center,
              style: AppText.labelCaps(size: 9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionState() {
    return TerraEmptyState(
      icon: Icons.no_photography_rounded,
      title: 'Camera permission required',
      message: 'Proteinix needs camera access to estimate your plate. '
          'You can still import a photo from your gallery.',
      accent: AppColors.error,
      action: Column(
        children: [
          SizedBox(
            width: 220,
            child: PillButton(
              label: 'Open settings',
              icon: Icons.settings_rounded,
              onPressed: () async {
                await openAppSettings();
                await Future.delayed(const Duration(milliseconds: 500));
                _initCamera();
              },
            ),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: _initCamera, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _controls() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _sideAction(Icons.photo_library_outlined, 'Import', _import),
                ShutterButton(onTap: _capture, busy: _busy),
                _sideAction(
                  _torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  'Flash',
                  _toggleTorch,
                  active: _torch,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _sideAction(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconBubble(
          icon: icon,
          size: 56,
          color: active ? AppColors.primary : AppColors.onSurface,
          background: AppColors.surfaceContainer,
          onTap: onTap,
        ),
        const SizedBox(height: 8),
        Text(label.toUpperCase(), style: AppText.labelCaps(size: 10)),
      ],
    );
  }

  void _showTips() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.page,
          right: AppSpacing.page,
          bottom: MediaQuery.of(ctx).padding.bottom + AppSpacing.md,
        ),
        child: TerraCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('For the best estimate'),
              const SizedBox(height: AppSpacing.sm),
              ...[
                'Fill most of the frame with the food',
                'Shoot in even light — avoid hard shadows',
                'Point straight down at the plate',
                'Add weights in the next step for precision',
              ].map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 18, color: AppColors.secondary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t, style: AppText.body())),
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
}
