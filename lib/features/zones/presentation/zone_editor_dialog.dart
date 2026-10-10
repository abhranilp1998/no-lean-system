import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_dialog.dart';
import '../domain/danger_zone.dart';

class ZoneDraft {
  const ZoneDraft({required this.name, required this.radiusMeters});

  final String name;
  final double radiusMeters;
}

/// Name + radius editor used for new pins and existing zones.
Future<ZoneDraft?> showZoneEditorDialog(
  BuildContext context, {
  required double latitude,
  required double longitude,
  DangerZone? existing,
}) => showDialog<ZoneDraft>(
  context: context,
  builder: (_) => _ZoneEditorDialog(
    latitude: latitude,
    longitude: longitude,
    existing: existing,
  ),
);

class _ZoneEditorDialog extends StatefulWidget {
  const _ZoneEditorDialog({
    required this.latitude,
    required this.longitude,
    this.existing,
  });

  final double latitude;
  final double longitude;
  final DangerZone? existing;

  @override
  State<_ZoneEditorDialog> createState() => _ZoneEditorDialogState();
}

class _ZoneEditorDialogState extends State<_ZoneEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late double _radius =
      widget.existing?.radiusMeters ?? DangerZone.defaultRadiusMeters;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > DangerZone.maxNameLength) {
      setState(
        () => _error = 'Name it in 1–${DangerZone.maxNameLength} characters.',
      );
      return;
    }
    Navigator.pop(context, ZoneDraft(name: name, radiusMeters: _radius));
  }

  static const _presets = [150.0, 300.0, 500.0, 1000.0];

  String _radiusLabel(double meters) => meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(meters % 1000 == 0 ? 0 : 1)} KM'
      : '${meters.round()} M';

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final shrinking = existing != null && _radius < existing.radiusMeters;
    return AppDialog(
      title: existing == null ? 'MARK DANGER ZONE' : 'EDIT DANGER ZONE',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: magenta.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: magenta.withValues(alpha: .35)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place, size: 13, color: magenta),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}',
                        style: microStyle.copyWith(color: magenta),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('zone-name'),
              controller: _name,
              maxLength: DangerZone.maxNameLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Name (e.g. the usual pharmacy)',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('RADIUS', style: eyebrowStyle.copyWith(color: red)),
                const Spacer(),
                Text(
                  _radiusLabel(_radius),
                  key: const ValueKey('zone-radius-value'),
                  style: displayFont(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: red,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: red,
                thumbColor: red,
                inactiveTrackColor: red.withValues(alpha: .18),
                overlayColor: red.withValues(alpha: .12),
                valueIndicatorColor: red,
              ),
              child: Slider(
                key: const ValueKey('zone-radius'),
                value: _radius,
                min: DangerZone.minRadiusMeters,
                max: DangerZone.maxRadiusMeters,
                divisions: 38,
                label: '${_radius.round()} m',
                onChanged: (value) => setState(() => _radius = value),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in _presets)
                  ChoiceChip(
                    key: ValueKey('zone-radius-${preset.round()}'),
                    label: Text(_radiusLabel(preset)),
                    labelStyle: microStyle.copyWith(
                      color: _radius == preset ? ink : red,
                      fontWeight: FontWeight.w700,
                    ),
                    selected: _radius == preset,
                    selectedColor: red,
                    backgroundColor: red.withValues(alpha: .08),
                    side: BorderSide(color: red.withValues(alpha: .45)),
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _radius = preset),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              shrinking
                  ? 'Shrinking a zone needs your PIN when the relapse lock is on.'
                  : 'Android geofencing is reliable from about 100–150 m. Larger zones alert earlier.',
              style: TextStyle(
                color: shrinking ? toxic : muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                FilledButton.icon(
                  key: const ValueKey('zone-save'),
                  onPressed: _save,
                  icon: const Icon(Icons.shield_outlined, size: 16),
                  style: FilledButton.styleFrom(
                    backgroundColor: red,
                    foregroundColor: ink,
                  ),
                  label: Text(existing == null ? 'ARM ZONE' : 'SAVE ZONE'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
