import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (value) => setState(() => _selectedTab = value),
        backgroundColor: panel.withValues(alpha: .96),
        indicatorColor: cyan.withValues(alpha: .15),
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
    );
  }
}
