import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/app_feedback.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/no_lean_visuals.dart';
import '../core/widgets/animated_background.dart';
import '../features/cravings/presentation/cravings_screen.dart';
import '../features/cravings/presentation/craving_dialog.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/emergency/presentation/emergency_screen.dart';
import '../features/progress/presentation/progress_screen.dart';
import '../features/recovery/application/recovery_provider.dart';
import '../features/recovery/domain/recovery_event.dart';
import '../features/recovery/presentation/relapse_cooldown_screen.dart';
import '../features/recovery/services/notification_service.dart';
import '../features/recovery/services/widget_action_service.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/timeline/presentation/timeline_screen.dart';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _selectedTab = 0;
  StreamSubscription<String>? _notificationActionSubscription;
  StreamSubscription<String>? _widgetActionSubscription;

  @override
  void initState() {
    super.initState();
    _notificationActionSubscription = NotificationService.instance.actionStream
        .listen(_handleNotificationAction);
    _widgetActionSubscription = WidgetActionService.instance.actionStream
        .listen(_handleWidgetAction);
    unawaited(WidgetActionService.instance.initialize());
  }

  @override
  void dispose() {
    _notificationActionSubscription?.cancel();
    _widgetActionSubscription?.cancel();
    super.dispose();
  }

  void _handleWidgetAction(String action) {
    if (!mounted) return;
    if (action == 'sos') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EmergencyScreen()),
      );
    } else if (action == 'craving') {
      final recovery = ref.read(recoveryProvider);
      if (recovery.relapseCooldownUntil == null) {
        setState(() => _selectedTab = 1);
        showCravingDialog(context, ref);
      }
    }
  }

  void _handleNotificationAction(String actionId) {
    if (!mounted) return;
    final recovery = ref.read(recoveryProvider);

    // If in cooldown, most actions just redirect to the cooldown screen anyway,
    // but SOS can still open.
    if (actionId == 'action_sos') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EmergencyScreen()),
      );
    } else if (actionId == 'action_safe') {
      if (recovery.relapseCooldownUntil == null) {
        recovery.appendEvent(
          RecoveryEvent.create(type: RecoveryEventType.cleanCheckIn),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Safe check-in recorded.'),
            backgroundColor: toxic,
          ),
        );
      }
    } else if (actionId == 'action_crave') {
      if (recovery.relapseCooldownUntil == null) {
        setState(() => _selectedTab = 1); // Switch to cravings tab
      }
    }
  }

  static const _pages = [
    DashboardScreen(),
    CravingsScreen(),
    ProgressScreen(),
    TimelineScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final visuals = NoLeanVisuals.of(context);
    final isInCooldown = recovery.relapseCooldownUntil != null;

    return Scaffold(
      body: Stack(
        children: [
          AnimatedBackground(
            risk: recovery.isRiskWindow,
            scanlines: recovery.scanlines && !recovery.reduceMotion,
          ),
          SafeArea(
            child: isInCooldown
                ? const RelapseCooldownScreen()
                : IndexedStack(index: _selectedTab, children: _pages),
          ),
        ],
      ),
      bottomNavigationBar: isInCooldown
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cyan.withValues(
                      alpha: visuals.accentOpacity(
                        visuals.highContrast ? .5 : .16,
                      ),
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
                    icon: Icon(Icons.history_outlined),
                    selectedIcon: Icon(Icons.history, color: cyan),
                    label: 'Timeline',
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
