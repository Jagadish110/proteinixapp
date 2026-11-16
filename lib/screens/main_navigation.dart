import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/strings.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/require_account.dart';
import '../widgets/ui/ui.dart';
import 'ai_coach/ai_coach_screen.dart';
import 'home/home_screen.dart';
import 'nutrition/nutrition_screen.dart';
import 'progress/progress_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  /// Index 2 is the capture action — it opens the scanner instead of a tab.
  static const _captureIndex = 2;

  static const _destinations = [
    NavDestination(icon: Icons.home_rounded, label: AppStrings.home),
    NavDestination(icon: Icons.restaurant_rounded, label: AppStrings.nutrition),
    NavDestination(icon: Icons.photo_camera_rounded, label: AppStrings.capture),
    NavDestination(icon: Icons.trending_up_rounded, label: AppStrings.progress),
    NavDestination(icon: Icons.smart_toy_rounded, label: AppStrings.coach),
  ];

  static const _pages = <Widget>[
    HomeScreen(),
    NutritionScreen(),
    SizedBox.shrink(), // capture slot
    ProgressScreen(),
    AiCoachScreen(),
  ];

  int _index = 0;
  final _visited = <int>{0};
  DateTime? _lastBackPress;

  void _onSelect(int i) {
    if (i == _captureIndex) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  void _handleBack(bool didPop) {
    if (didPop) return;
    if (_index != 0) {
      setState(() => _index = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handleBack(didPop),
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        // This shell has no text input of its own — every tab underneath
        // manages its own Scaffold and keyboard inset. Letting this outer
        // Scaffold ALSO resize for the keyboard means both fight over the
        // same inset whenever a tab (e.g. AI Coach's chat composer) shows
        // the keyboard, which is what caused the flicker / lost focus.
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: List.generate(_pages.length, (i) {
            if (i == _captureIndex || !_visited.contains(i)) {
              return const SizedBox.shrink();
            }
            final active = _index == i;
            // TickerMode halts the background tabs' animations; the boundary
            // keeps each tab's painting independent of its siblings.
            return Offstage(
              offstage: !active,
              child: TickerMode(
                enabled: active,
                child: RepaintBoundary(child: _pages[i]),
              ),
            );
          }),
        ),
        bottomNavigationBar: FloatingNavBar(
          destinations: _destinations,
          currentIndex: _index,
          captureIndex: _captureIndex,
          onSelect: _onSelect,
          onCapture: () async {
            if (!await requireAccount(context, action: 'scan a meal')) return;
            if (context.mounted) context.push('/scan');
          },
        ),
      ),
    );
  }
}
