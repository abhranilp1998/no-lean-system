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

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.existing == null ? 'MARK DANGER ZONE' : 'EDIT DANGER ZONE',
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.latitude.toStringAsFixed(5)}, ${widget.longitude.toStringAsFixed(5)}',
              style: microStyle.copyWith(color: magenta),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 8),
            Text(
              'RADIUS // ${_radius.round()} M',
              style: microStyle.copyWith(color: cyan),
            ),
            Slider(
              key: const ValueKey('zone-radius'),
              value: _radius,
              min: DangerZone.minRadiusMeters,
              max: DangerZone.maxRadiusMeters,
              divisions: 38,
              label: '${_radius.round()} m',
              onChanged: (value) => setState(() => _radius = value),
            ),
            const Text(
              'Android geofencing is reliable from about 100–150 m. Larger zones alert earlier.',
              style: TextStyle(color: muted, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                FilledButton(
                  key: const ValueKey('zone-save'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(backgroundColor: magenta),
                  child: const Text('SAVE ZONE'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
