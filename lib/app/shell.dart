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
import '../features/recovery/presentation/relapse_log_sheet.dart';
import '../core/services/app_notice.dart';
import '../features/recovery/services/notification_service.dart';
import '../features/recovery/services/widget_action_service.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/timeline/presentation/timeline_screen.dart';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> with WidgetsBindingObserver {
  bool _handlingAction = false;
  bool _sosOpen = false;
  final _pendingActions = <String>[];
  int _selectedTab = 0;
  StreamSubscription<String>? _notificationActionSubscription;
  StreamSubscription<String>? _widgetActionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationActionSubscription = NotificationService.instance.actionStream
        .listen(_handleNotificationAction);
    _widgetActionSubscription = WidgetActionService.instance.actionStream
        .listen(_handleWidgetAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(recoveryProvider).markOpened());
      unawaited(WidgetActionService.instance.initialize());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationActionSubscription?.cancel();
    _widgetActionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(recoveryProvider).markOpened());
      unawaited(WidgetActionService.instance.initialize());
    }
  }

  void _handleWidgetAction(String action) {
    if (!mounted) return;
    if (action == 'sos') {
      if (_sosOpen) return;
      _sosOpen = true;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EmergencyScreen()),
      ).whenComplete(() => _sosOpen = false);
      return;
    }
    // Repeated taps while the same sheet is open do not stack duplicate forms.
    if (_handlingAction && action != 'sos') return;
    _pendingActions.add(action);
    unawaited(_drainActions());
  }

  Future<void> _drainActions() async {
    if (_handlingAction || !mounted) return;
    _handlingAction = true;
    try {
      while (_pendingActions.isNotEmpty) {
        if (!mounted) return;
        final action = _pendingActions.removeAt(0);
        if (action == 'sos') {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EmergencyScreen()),
          );
        } else if (action == 'craving') {
          setState(() => _selectedTab = 1);
          await showCravingDialog(context, ref);
        } else if (action == 'relapse') {
          await showRelapseLogSheet(context, source: 'widget');
        }
      }
    } finally {
      _handlingAction = false;
    }
  }

  void _handleNotificationAction(String actionId) {
    if (!mounted) return;
    if (actionId == 'action_sos') {
      _handleWidgetAction('sos');
    } else if (actionId == 'action_crave') {
      _handleWidgetAction('craving');
    } else if (actionId == 'action_safe') {
      unawaited(_checkIn());
    }
  }

  Future<void> _checkIn() async {
    try {
      await ref
          .read(recoveryProvider)
          .appendEvent(
            RecoveryEvent.create(type: RecoveryEventType.cleanCheckIn),
          );
      if (mounted) {
        AppNotice.show(
          context,
          'Safe check-in recorded.',
          type: AppNoticeType.success,
        );
      }
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'Check-in could not be saved. Please try again.',
          type: AppNoticeType.error,
        );
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

    return Scaffold(
      body: Stack(
        children: [
          AnimatedBackground(
            risk: recovery.isRiskWindow,
            scanlines: recovery.scanlines && !recovery.reduceMotion,
          ),
          SafeArea(
            child: Column(
              children: [
                if (recovery.saveMessage != null)
                  MaterialBanner(
                    content: Text(recovery.saveMessage!),
                    actions: [
                      TextButton(
                        onPressed: () => AppNotice.show(
                          context,
                          'Retry the action to save it. Your previous history is still intact.',
                        ),
                        child: const Text('INFO'),
                      ),
                    ],
                  ),
                Expanded(
                  child: IndexedStack(index: _selectedTab, children: _pages),
                ),
              ],
            ),
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
