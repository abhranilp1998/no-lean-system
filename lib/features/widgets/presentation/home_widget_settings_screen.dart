import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recovery/application/recovery_provider.dart';
import '../../zones/domain/danger_zone.dart';
import '../domain/fullscreen_widgets.dart';
import '../domain/garden.dart';
import '../services/widget_choice_service.dart';
import 'garden_painter.dart';
import 'radar_painter.dart';

/// Settings > Home screen widget: what a stretched NO LEAN widget (and the
/// NO LEAN Full widget) shows, for every widget or per placed widget.
class HomeWidgetSettingsScreen extends ConsumerStatefulWidget {
  const HomeWidgetSettingsScreen({super.key, this.service});

  final WidgetChoiceService? service;

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const HomeWidgetSettingsScreen()));

  @override
  ConsumerState<HomeWidgetSettingsScreen> createState() =>
      _HomeWidgetSettingsScreenState();
}

class _HomeWidgetSettingsScreenState
    extends ConsumerState<HomeWidgetSettingsScreen> {
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

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final chosen = recovery.stretchedWidgetView;
    final garden = Garden.fromEvents(recovery.events, DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('HOME SCREEN WIDGET')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'What a NO LEAN widget shows when you stretch it big, and what '
            'the NO LEAN Full widget shows at any size. Tap the small corner '
            'button on a widget to cycle its view.',
          ),
          if (recovery.widgetPrivacy) ...[
            const SizedBox(height: 8),
            const Text(
              'Widget privacy is on, so widgets show the neutral view.',
              key: Key('stretched-privacy-note'),
            ),
          ],
          const SizedBox(height: 16),
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
          if (_placed.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'PLACED WIDGETS',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            for (final placed in _placed)
              ListTile(
                key: Key('placed-widget-${placed.id}'),
                title: Text('${placed.label} #${placed.id}'),
                trailing: DropdownButton<StretchedWidgetView?>(
                  value: placed.override,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Same as above'),
                    ),
                    for (final v in StretchedWidgetView.values)
                      DropdownMenuItem(value: v, child: Text(v.label)),
                  ],
                  onChanged: (v) async {
                    await _service.setOverride(placed.id, v);
                    await _reload();
                  },
                ),
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
