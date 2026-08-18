import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/no_lean_visuals.dart';
import '../../../core/widgets/glass_card.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../application/recovery_provider.dart';

class RelapseCooldownScreen extends ConsumerStatefulWidget {
  const RelapseCooldownScreen({super.key});

  @override
  ConsumerState<RelapseCooldownScreen> createState() =>
      _RelapseCooldownScreenState();
}

class _RelapseCooldownScreenState extends ConsumerState<RelapseCooldownScreen> {
  Timer? _timer;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _checkTimer();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _checkTimer());
  }

  void _checkTimer() {
    final recovery = ref.read(recoveryProvider);
    final unlockTime = recovery.relapseCooldownUntil ?? DateTime.now();
    if (DateTime.now().isAfter(unlockTime) && !_unlocked) {
      setState(() {
        _unlocked = true;
      });
      _timer?.cancel();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _completeDebrief(String reason) async {
    AppFeedback.success();
    final recovery = ref.read(recoveryProvider);
    await recovery.clearRelapseCooldown(reason);
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final visuals = NoLeanVisuals.of(context);

    if (_unlocked) {
      return _DebriefView(onComplete: _completeDebrief);
    }

    final unlockTime = recovery.relapseCooldownUntil ?? DateTime.now();
    final remaining = unlockTime.difference(DateTime.now());
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Text(
                'STREAK LOST.',
                style: TextStyle(
                  fontFamily: 'NoLeanDisplay',
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: red,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'SYSTEM LOCKED. READ YOUR REASONS.',
                style: TextStyle(
                  fontFamily: 'NoLeanMono',
                  fontSize: 12,
                  color: muted,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  border: Border.all(color: red.withValues(alpha: visuals.accentOpacity(.3))),
                  borderRadius: BorderRadius.circular(16),
                  color: red.withValues(alpha: .05),
                ),
                child: Text(
                  '$minutes:$seconds',
                  style: const TextStyle(
                    fontFamily: 'NoLeanMono',
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 48),
              if (recovery.reasons.isNotEmpty) ...[
                Text(
                  'YOUR REASONS FOR QUITTING:',
                  style: eyebrowStyle.copyWith(color: red),
                ),
                const SizedBox(height: 16),
                Expanded(
                  flex: 2,
                  child: ListView.separated(
                    itemCount: recovery.reasons.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => GlassCard(
                      accent: muted,
                      child: Text(
                        recovery.reasons[index],
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ] else
                const Spacer(flex: 2),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  AppFeedback.tap();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EmergencyScreen(),
                      fullscreenDialog: true,
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: purple,
                  foregroundColor: Colors.white,
                ),
                child: const Text('EMERGENCY SOS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebriefView extends StatelessWidget {
  const _DebriefView({required this.onComplete});

  final ValueChanged<String> onComplete;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'LOCK LIFTED.',
                style: TextStyle(
                  fontFamily: 'NoLeanDisplay',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: cyan,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'What led to this relapse?',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              _DebriefButton(
                label: 'CRAVING / URGE',
                onTap: () => onComplete('craving'),
              ),
              const SizedBox(height: 16),
              _DebriefButton(
                label: 'STRESS / ANXIETY',
                onTap: () => onComplete('stress'),
              ),
              const SizedBox(height: 16),
              _DebriefButton(
                label: 'BOREDOM / HABIT',
                onTap: () => onComplete('boredom'),
              ),
              const SizedBox(height: 16),
              _DebriefButton(
                label: 'SOCIAL PRESSURE',
                onTap: () => onComplete('social'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebriefButton extends StatelessWidget {
  const _DebriefButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: GlassCard(
        accent: cyan,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'NoLeanMono',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
