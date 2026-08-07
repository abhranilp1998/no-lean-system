import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
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
          const Icon(Icons.chevron_right, color: muted, size: 18),
        ],
      ),
    ),
  );
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
      onChanged: onChanged,
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
  Widget build(BuildContext context) => GlassCard(
    accent: purple,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('EFFECT INTENSITY', style: microStyle.copyWith(color: purple)),
        const SizedBox(height: 10),
        SegmentedButton<EffectIntensity>(
          segments: const [
            ButtonSegment(value: EffectIntensity.calm, label: Text('CALM')),
            ButtonSegment(
              value: EffectIntensity.standard,
              label: Text('STANDARD'),
            ),
            ButtonSegment(
              value: EffectIntensity.aggressive,
              label: Text('AGGRESSIVE'),
            ),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
          style: ButtonStyle(
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 9, fontFamily: 'NoLeanMono'),
            ),
            side: WidgetStatePropertyAll(
              BorderSide(color: purple.withValues(alpha: .35)),
            ),
          ),
        ),
      ],
    ),
  );
}
