import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../zones/domain/danger_zone.dart';
import '../domain/fullscreen_widgets.dart';
import '../domain/garden.dart';
import '../services/widget_choice_service.dart';
import 'garden_painter.dart';
import 'radar_painter.dart';

/// Settings > Widgets: every widget setting in one place. A live preview of
/// each widget the launcher offers, an "Add to home screen" button, what
/// NO LEAN Full shows, widget privacy, and per-placed-widget views.
class WidgetsScreen extends ConsumerStatefulWidget {
  const WidgetsScreen({super.key, this.service});

  final WidgetChoiceService? service;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const WidgetsScreen()));

  @override
  ConsumerState<WidgetsScreen> createState() => _WidgetsScreenState();
}

class _WidgetsScreenState extends ConsumerState<WidgetsScreen> {
  late final WidgetChoiceService _service =
      widget.service ?? WidgetChoiceService();
  List<PlacedWidget> _placed = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final placed = await _service.placed();
    if (mounted) setState(() => _placed = placed);
  }

  Future<void> _add(WidgetKind kind) async {
    final pinned = await _service.pin(kind);
    if (!mounted) return;
    if (pinned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confirm on the home screen prompt.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('widget-add-steps'),
        title: Text('Add ${kind.title}'),
        content: Text(
          '1. Long-press an empty spot on your home screen.\n'
          '2. Tap Widgets.\n'
          '3. Find NO LEAN and drag "${kind.title}" onto the screen.\n\n'
          'Just updated? If it is missing, restart the phone once: some '
          'launchers only refresh their widget list then.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final chosen = recovery.stretchedWidgetView;
    final garden = Garden.fromEvents(recovery.events, DateTime.now());
    final label = Theme.of(context).textTheme.labelLarge;
    return Scaffold(
      appBar: AppBar(title: const Text('WIDGETS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            key: const ValueKey('widgets-privacy'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Private widgets'),
            subtitle: Text(
              recovery.widgetPrivacy
                  ? 'Neutral labels // no counter, streak or risk state'
                  : 'Widgets show clean time, streak and risk window',
            ),
            value: recovery.widgetPrivacy,
            onChanged: (v) => recovery.setWidgetPrivacy(v),
          ),
          const SizedBox(height: 8),
          Text('YOUR WIDGETS', style: label),
          const SizedBox(height: 8),
          for (final kind in WidgetKind.values)
            _KindCard(
              kind: kind,
              preview: kind == WidgetKind.full
                  ? AspectRatio(
                      aspectRatio: 1.6,
                      child: CustomPaint(
                        painter: StretchedPreviewPainter(
                          recovery.widgetPrivacy
                              ? StretchedWidgetView.nightTimeline
                              : chosen,
                          garden,
                          recovery.zones,
                        ),
                      ),
                    )
                  : _ClassicPreview(kind: kind, recovery: recovery),
              onAdd: () => _add(kind),
            ),
          const SizedBox(height: 16),
          Text('NO LEAN FULL SHOWS', style: label),
          const SizedBox(height: 4),
          const Text(
            'Auto changes with the time of day. Your 2x1, 4x2 and 4x3 '
            'widgets keep their classic look unless you pick a view for '
            'one of them below.',
          ),
          if (recovery.widgetPrivacy) ...[
            const SizedBox(height: 8),
            const Text(
              'Widget privacy is on, so widgets show the neutral view.',
              key: Key('stretched-privacy-note'),
            ),
          ],
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.8,
            children: [
              for (final view in StretchedWidgetView.values)
                _ChoiceCard(
                  view: view,
                  selected: view == chosen,
                  garden: garden,
                  zones: recovery.zones,
                  onTap: () => recovery.setStretchedWidgetView(view),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text('ON YOUR HOME SCREEN', style: label),
          if (_placed.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No NO LEAN widgets placed yet.'),
            ),
          for (final placed in _placed)
            ListTile(
              key: Key('placed-widget-${placed.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(placed.label),
              subtitle: placed.isLegacy
                  ? const Text(
                      'Still works. To change its view, add NO LEAN Full '
                      'instead.',
                    )
                  : null,
              trailing: placed.canChooseView
                  ? DropdownButton<StretchedWidgetView?>(
                      value: placed.override,
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            placed.isFull ? 'Same as above' : 'Classic',
                          ),
                        ),
                        for (final v in StretchedWidgetView.values)
                          DropdownMenuItem(value: v, child: Text(v.label)),
                      ],
                      onChanged: (v) async {
                        await _service.setOverride(placed.id, v);
                        await _reload();
                      },
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.kind,
    required this.preview,
    required this.onAdd,
  });

  final WidgetKind kind;
  final Widget preview;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('widget-kind-${kind.native}'),
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(16), child: preview),
          const SizedBox(height: 8),
          Text(kind.title, style: Theme.of(context).textTheme.titleMedium),
          Text(kind.description),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: Key('widget-add-${kind.native}'),
              onPressed: onAdd,
              icon: const Icon(Icons.add_to_home_screen),
              label: const Text('Add to home screen'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Live preview of the classic widgets from current data.
class _ClassicPreview extends StatelessWidget {
  const _ClassicPreview({required this.kind, required this.recovery});

  final WidgetKind kind;
  final RecoveryController recovery;

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF4DE0FF);
    const lime = Color(0xFFBEFF50);
    final private = recovery.widgetPrivacy;
    final d = recovery.cleanDuration;
    final counter = private
        ? 'Open'
        : '${d.inDays}d ${(d.inHours % 24).toString().padLeft(2, '0')}:'
              '${(d.inMinutes % 60).toString().padLeft(2, '0')}';
    final buttons = private
        ? const ['OPEN', 'NOTE']
        : const ['SOS', 'LOG CRAVING', 'LOG RELAPSE', 'CODE INSTEAD'];
    final tall = kind == WidgetKind.large;
    return Container(
      color: const Color(0xFF131824),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            private ? 'NO LEAN' : 'NO LEAN // LIVE',
            style: const TextStyle(color: cyan, fontFamily: 'monospace'),
          ),
          Text(
            counter,
            key: Key('widget-preview-counter-${kind.native}'),
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: kind == WidgetKind.large ? 34 : 26,
            ),
          ),
          if (!private && kind != WidgetKind.small)
            Text(
              '${recovery.streak} DAYS CLEAN',
              style: const TextStyle(color: lime, fontFamily: 'monospace'),
            ),
          if (kind != WidgetKind.small) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final b in buttons)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: tall ? 12 : 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: cyan),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      b,
                      style: const TextStyle(color: cyan, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.view,
    required this.selected,
    required this.garden,
    required this.zones,
    required this.onTap,
  });

  final StretchedWidgetView view;
  final bool selected;
  final Garden garden;
  final List<DangerZone> zones;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      key: Key('stretched-choice-${view.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(
                  painter: StretchedPreviewPainter(view, garden, zones),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    view.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (selected) Icon(Icons.check_circle, color: accent, size: 18),
              ],
            ),
            Text(
              view.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail for each choice. Garden and map use the real widget painters.
class StretchedPreviewPainter extends CustomPainter {
  StretchedPreviewPainter(this.view, this.garden, this.zones);

  final StretchedWidgetView view;
  final Garden garden;
  final List<DangerZone> zones;

  static const _bg = Color(0xFF070B16);
  static const _cyan = Color(0xFF29E7FF);
  static const _muted = Color(0xFF6B7A90);

  @override
  void paint(Canvas canvas, Size size) {
    switch (view) {
      case StretchedWidgetView.garden:
        paintGarden(canvas, size, garden);
      case StretchedWidgetView.map:
        paintRadar(canvas, size, zones);
      case StretchedWidgetView.auto:
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width / 2, size.height));
        paintGarden(canvas, size, garden, evening: true);
        canvas.restore();
        canvas.save();
        canvas.translate(size.width / 2, 0);
        _shield(canvas, Size(size.width / 2, size.height));
        canvas.restore();
      case StretchedWidgetView.eveningShield:
        _shield(canvas, size);
      case StretchedWidgetView.nightTimeline:
        _background(canvas, size);
        for (var i = 0; i < 4; i++) {
          final y = size.height * (0.2 + i * 0.18);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(size.width * 0.1, y, size.width * 0.8, 10),
              const Radius.circular(4),
            ),
            Paint()..color = i < 2 ? _cyan : _muted,
          );
        }
      case StretchedWidgetView.wave:
        _background(canvas, size);
        final path = Path();
        for (var x = 0.0; x <= size.width; x += 2) {
          final t = x / size.width;
          final y =
              size.height *
              (0.65 - 0.35 * math.exp(-math.pow((t - 0.45) * 4, 2)));
          x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = _cyan
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      case StretchedWidgetView.note:
        _background(canvas, size);
        final r = Rect.fromCenter(
          center: size.center(Offset.zero),
          width: size.width * 0.7,
          height: size.width * 0.45,
        );
        final stroke = Paint()
          ..color = _cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawRect(r, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(r.left, r.top)
            ..lineTo(r.center.dx, r.center.dy + 4)
            ..lineTo(r.right, r.top),
          stroke,
        );
    }
  }

  void _background(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

  void _shield(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF3A0A14),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.12,
            size.height * (0.38 + i * 0.19),
            size.width * 0.76,
            size.height * 0.13,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFFE5395B),
      );
    }
  }

  @override
  bool shouldRepaint(StretchedPreviewPainter old) =>
      old.view != view || old.garden != garden || old.zones != zones;
}
