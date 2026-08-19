import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/app_feedback.dart';
import '../core/theme/app_theme.dart';
import '../features/recovery/application/recovery_provider.dart';
import 'shell.dart';

class NoLeanApp extends ConsumerWidget {
  const NoLeanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(recoveryProvider);
    final effectScale = switch (recovery.intensity.index) {
      0 => .62,
      2 => 1.42,
      3 => 2.05,
      _ => 1.0,
    };

    AppFeedback.configure(
      soundEnabled: recovery.soundscape,
      vibrationEnabled: recovery.hapticFeedback,
      effectIntensity: recovery.intensity.index,
      soundEffect: recovery.feedbackSound,
    );

    return MaterialApp(
      title: 'NO LEAN',
      debugShowCheckedModeBanner: false,
      theme: buildNoLeanTheme(
        highContrast: recovery.highContrast,
        reduceMotion: recovery.reduceMotion,
        effectScale: effectScale,
      ),
      themeAnimationDuration: recovery.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        Widget result = MediaQuery(
          data: media.copyWith(
            disableAnimations: media.disableAnimations || recovery.reduceMotion,
          ),
          child: child ?? const SizedBox.shrink(),
        );

        if (recovery.highContrast) {
          result = ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              1.14,
              0,
              0,
              0,
              -12,
              0,
              1.14,
              0,
              0,
              -12,
              0,
              0,
              1.14,
              0,
              -12,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: result,
          );
        }
        return result;
      },
      home: recovery.isLoaded ? const Shell() : const _LoadingScreen(),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NO LEAN',
              style: TextStyle(
                fontFamily: 'NoLeanDisplay',
                color: cyan,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 18),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: cyan, strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
