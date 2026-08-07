import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/app_feedback.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/no_lean_visuals.dart';
import '../core/widgets/animated_background.dart';
import '../features/cravings/presentation/cravings_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/progress/presentation/progress_screen.dart';
import '../features/recovery/application/recovery_provider.dart';
import '../features/settings/presentation/settings_screen.dart';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _selectedTab = 0;

  static const _pages = [
    DashboardScreen(),
    CravingsScreen(),
    ProgressScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final visuals = NoLeanVisuals.of(context);
    return Scaffold(
      body: Stack(
        children: [
          AnimatedBackground(
            risk: recovery.isRiskWindow,
            scanlines: recovery.scanlines && !recovery.reduceMotion,
          ),
          SafeArea(
            child: IndexedStack(index: _selectedTab, children: _pages),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cyan.withValues(
                alpha: visuals.accentOpacity(visuals.highContrast ? .5 : .16),
              ),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: cyan.withValues(alpha: visuals.glowOpacity(.08)),
              blurRadius: 18 * visuals.glowRadiusScale,
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: (value) {
            if (value == _selectedTab) return;
            AppFeedback.selection();
            setState(() => _selectedTab = value);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.timer_outlined),
              selectedIcon: Icon(Icons.timer, color: cyan),
              label: 'Counter',
            ),
            NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt, color: cyan),
              label: 'Cravings',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights, color: cyan),
              label: 'Progress',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune, color: cyan),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
