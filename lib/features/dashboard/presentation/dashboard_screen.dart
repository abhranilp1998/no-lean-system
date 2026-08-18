import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/action_tile.dart';
import '../../../core/widgets/brand_header.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glow_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../../recovery/domain/event_derived_state.dart';
import '../../../core/widgets/status_pill.dart';
import '../../cravings/presentation/craving_dialog.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../../recovery/application/recovery_provider.dart';
import 'dashboard_dialogs.dart';
import 'widgets/animated_counter.dart';
import 'widgets/risk_window_banner.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    return RefreshIndicator(
      color: cyan,
      backgroundColor: panel,
      onRefresh: () async => ref.read(recoveryProvider).syncWidget(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
        children: [
          const BrandHeader(),
          const SizedBox(height: 22),
          if (recovery.isRiskWindow)
            RiskWindowBanner(windowLabel: recovery.riskWindow.label),
          if (recovery.isRiskWindow) const SizedBox(height: 14),
          Text('THE COUNTER', style: eyebrowStyle.copyWith(color: cyan)),
          const SizedBox(height: 6),
          Text(
            'No debate. No purchase.',
            style: displayFont(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 18),
          GlassCard(
            accent: recovery.isRiskWindow ? red : cyan,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatusPill(
                      label: recovery.isRiskWindow
                          ? 'RISK WINDOW'
                          : 'SYSTEM STABLE',
                      color: recovery.isRiskWindow ? red : toxic,
                    ),
                    Text(
                      'LIVE SINCE ${DateFormat('MMM d • HH:mm').format(recovery.lastDose)}',
                      style: microStyle,
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                AnimatedCounter(
                  duration: recovery.cleanDuration,
                  reduceMotion: recovery.reduceMotion,
                ),
                const SizedBox(height: 25),
                Text(
                  'CLEAN TIME',
                  style: eyebrowStyle.copyWith(
                    color: muted,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GlowButton(
            label: 'I WILL NOT BUY LEAN TODAY',
            icon: Icons.lock_outline,
            color: magenta,
            onTap: () => showPledgeDialog(context, ref),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'CURRENT STREAK',
                  value: '${recovery.streak}D',
                  detail: 'Keep the line clean',
                  color: cyan,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'MONEY SAVED',
                  value: money(recovery.moneySaved),
                  detail: 'At ${money(recovery.dailySpend)} / day',
                  color: toxic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'LONGEST STREAK',
                  value: '${recovery.longestStreak}D',
                  detail: 'Beat your record',
                  color: purple,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatCard(
                  label: 'LOGGED CRAVINGS',
                  value: '${recovery.cravings.length}',
                  detail: 'Awareness is data',
                  color: magenta,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text('ADAPTIVE INSIGHT', style: eyebrowStyle.copyWith(color: magenta)),
          const SizedBox(height: 10),
          _RiskSuggestionCard(events: recovery.events),
          const SizedBox(height: 22),
          Text('FAST INTERRUPTS', style: eyebrowStyle.copyWith(color: muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ActionTile(
                  icon: Icons.sos,
                  title: 'SOS MODE',
                  subtitle: '60 sec override',
                  color: red,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmergencyScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionTile(
                  icon: Icons.bolt,
                  title: 'LOG CRAVING',
                  subtitle: 'Name the trigger',
                  color: cyan,
                  onTap: () => showCravingDialog(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ActionTile(
            icon: Icons.code,
            title: 'CODE INSTEAD',
            subtitle: 'A small task beats a big spiral',
            color: purple,
            onTap: () => showCodeChallenge(context),
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'TODAY\'S CHECK-IN',
            action: 'OPEN',
            onTap: () => showCheckInDialog(context, ref),
          ),
          const SizedBox(height: 10),
          GlassCard(
            accent:
                recovery.lastPledge != null &&
                    DateUtils.isSameDay(recovery.lastPledge, DateTime.now())
                ? toxic
                : magenta,
            child: Row(
              children: [
                Icon(
                  recovery.lastPledge != null &&
                          DateUtils.isSameDay(
                            recovery.lastPledge,
                            DateTime.now(),
                          )
                      ? Icons.verified
                      : Icons.pending_actions,
                  color:
                      recovery.lastPledge != null &&
                          DateUtils.isSameDay(
                            recovery.lastPledge,
                            DateTime.now(),
                          )
                      ? toxic
                      : magenta,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    recovery.lastPledge != null &&
                            DateUtils.isSameDay(
                              recovery.lastPledge,
                              DateTime.now(),
                            )
                        ? 'Pledge locked for today. You made the decision before the urge.'
                        : 'Morning pledge is still open. Make the decision while it is yours.',
                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskSuggestionCard extends StatelessWidget {
  const _RiskSuggestionCard({required this.events});
  
  final List<dynamic> events;

  @override
  Widget build(BuildContext context) {
    // We cast to List<RecoveryEvent> because the import is available.
    // wait, RecoveryEvent is from domain
    final highRisk = computeHighRiskHours(events as dynamic); // Type hack to avoid another import if needed, but we imported event_derived_state.dart
    
    if (highRisk.isEmpty) {
      return const GlassCard(
        accent: magenta,
        child: Text(
          'Log more cravings to unlock personalized risk window suggestions.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.4),
        ),
      );
    }
    
    final topHours = highRisk.take(2).map((h) => '${h.toString().padLeft(2, '0')}:00').join(' & ');
    return GlassCard(
      accent: magenta,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: magenta, size: 18),
              const SizedBox(width: 8),
              Text('HIGH RISK DETECTED', style: microStyle.copyWith(color: magenta)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Based on your logs, you are most vulnerable around $topHours. Consider updating your risk window in Settings.',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
