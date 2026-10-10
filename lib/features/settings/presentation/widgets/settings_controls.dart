import 'package:flutter/material.dart';

import '../../../../core/services/app_feedback.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/no_lean_visuals.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../recovery/domain/effect_intensity.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: eyebrowStyle.copyWith(color: muted)),
        const SizedBox(height: 9),
        ...children.map(
          (child) =>
              Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
        ),
      ],
    ),
  );
}

class SettingAction extends StatelessWidget {
  const SettingAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  /// Null renders a disabled, dimmed tile (e.g. "coming soon").
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    final tile = InkWell(
      onTap: tap == null
          ? null
          : () {
              AppFeedback.tap();
              tap();
            },
      borderRadius: BorderRadius.circular(14),
      child: GlassCard(
        accent: color,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10.5, color: muted),
                  ),
                ],
              ),
            ),
            Icon(
              tap == null ? Icons.lock_clock_outlined : Icons.chevron_right,
              color: muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
    return tap == null ? Opacity(opacity: .5, child: tile) : tile;
  }
}

class SettingToggle extends StatelessWidget {
  const SettingToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final Color color;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GlassCard(
    accent: value ? color : muted,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 10.5, color: muted),
      ),
      value: value,
      activeThumbColor: color,
      onChanged: (value) {
        AppFeedback.selection();
        onChanged(value);
      },
    ),
  );
}

class SettingIntensity extends StatelessWidget {
  const SettingIntensity({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final EffectIntensity value;
  final ValueChanged<EffectIntensity> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = value == EffectIntensity.ultra ? magenta : purple;
    return GlassCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'EFFECT INTENSITY',
                style: microStyle.copyWith(color: accent),
              ),
              if (value == EffectIntensity.ultra) ...[
                const Spacer(),
                Text(
                  '/// GLYPH OVERDRIVE',
                  style: microStyle.copyWith(color: cyan, fontSize: 8),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final intensity in EffectIntensity.values)
                Expanded(
                  child: _IntensitySegment(
                    intensity: intensity,
                    selected: value == intensity,
                    onTap: () {
                      if (value == intensity) return;
                      AppFeedback.selection();
                      onChanged(intensity);
                    },
                  ),
                ),
            ],
          ),
          if (value == EffectIntensity.ultra) ...[
            const SizedBox(height: 9),
            Text(
              'MAX BLOOM // ACTIVE GLYPHS // CHROMATIC GLITCH SURGE',
              style: microStyle.copyWith(color: magenta, fontSize: 8),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntensitySegment extends StatelessWidget {
  const _IntensitySegment({
    required this.intensity,
    required this.selected,
    required this.onTap,
  });

  final EffectIntensity intensity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    final accent = intensity == EffectIntensity.ultra ? magenta : purple;
    final label = switch (intensity) {
      EffectIntensity.calm => 'CALM',
      EffectIntensity.standard => 'STANDARD',
      EffectIntensity.aggressive => 'AGGRESSIVE',
      EffectIntensity.ultra => 'ULTRA',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label effect intensity',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: visuals.motionDuration(const Duration(milliseconds: 160)),
            height: 42,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: .92)
                  : Colors.black.withValues(alpha: .24),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: accent.withValues(alpha: selected ? .95 : .28),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(
                          alpha: visuals.glowOpacity(.28),
                        ),
                        blurRadius: 12 * visuals.glowRadiusScale,
                      ),
                    ]
                  : null,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                selected ? '✓  $label' : label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontFamily: 'NoLeanMono',
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
