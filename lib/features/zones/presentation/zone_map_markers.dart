import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/app_feedback.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/no_lean_visuals.dart';
import '../../../core/widgets/glass_card.dart';
import '../domain/danger_zone.dart';

enum MapMode { street, fallback, grid }

/// Glow ring + core circle for one zone.
List<CircleMarker> zoneCircles(LatLng point, double radiusMeters) => [
  CircleMarker(
    point: point,
    radius: radiusMeters,
    useRadiusInMeter: true,
    color: Colors.transparent,
    borderColor: red.withValues(alpha: .22),
    borderStrokeWidth: 9,
  ),
  CircleMarker(
    point: point,
    radius: radiusMeters,
    useRadiusInMeter: true,
    color: red.withValues(alpha: .15),
    borderColor: red,
    borderStrokeWidth: 2,
  ),
];

class MapStatusChip extends StatelessWidget {
  const MapStatusChip({required this.mode, super.key});

  final MapMode mode;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (mode) {
      MapMode.street => ('OSM // LIVE + CACHE', cyan, Icons.public),
      MapMode.fallback => ('NO SIGNAL // GRID FALLBACK', toxic, Icons.grid_on),
      MapMode.grid => ('OFFLINE GRID', toxic, Icons.grid_on),
    };
    return DecoratedBox(
      key: const ValueKey('map-status'),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
            Text(label, style: microStyle.copyWith(color: color, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class MapControlButton extends StatelessWidget {
  const MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = cyan,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: ink.withValues(alpha: .82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: enabled ? .6 : .2)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed == null
              ? null
              : () {
                  AppFeedback.selection();
                  onPressed!();
                },
          child: SizedBox.square(
            dimension: 38,
            child: Icon(
              icon,
              size: 19,
              color: enabled ? color : color.withValues(alpha: .3),
            ),
          ),
        ),
      ),
    );
  }
}

/// Map control bar button in the app's glow style; supports a disabled state.
class HudActionButton extends StatelessWidget {
  const HudActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.filled = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final visuals = NoLeanVisuals.of(context);
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          if (enabled)
            BoxShadow(
              color: color.withValues(alpha: visuals.glowOpacity(.26)),
              blurRadius: 16 * visuals.glowRadiusScale,
            ),
        ],
      ),
      child: OutlinedButton.icon(
        onPressed: onPressed == null
            ? null
            : () {
                AppFeedback.tap(strength: AppFeedbackStrength.strong);
                onPressed!();
              },
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: displayFont(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: color.withValues(alpha: .35),
          backgroundColor: color.withValues(alpha: filled ? .18 : .06),
          side: BorderSide(color: color.withValues(alpha: enabled ? .75 : .25)),
          minimumSize: const Size.fromHeight(50),
          enableFeedback: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Danger pin: a glowing diamond centred on the exact point, name tag above.
class ZonePinMarker extends StatelessWidget {
  const ZonePinMarker({required this.label, super.key});

  static const double width = 132;
  static const double height = 76;

  /// The diamond sits at the widget centre, so the marker centres on the point.
  static const alignment = Alignment.center;

  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: height / 2 + 16,
            child: Container(
              constraints: const BoxConstraints(maxWidth: width),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ink.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: red.withValues(alpha: .7)),
              ),
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                ),
              ),
            ),
          ),
          Transform.rotate(
            angle: .785398, // 45°
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: red.withValues(alpha: .9),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(color: red.withValues(alpha: .8), blurRadius: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MyLocationMarker extends StatelessWidget {
  const MyLocationMarker({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cyan,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: cyan.withValues(alpha: .9), blurRadius: 12),
          ],
        ),
      ),
    ),
  );
}

class ZoneListCard extends StatelessWidget {
  const ZoneListCard({
    required this.zone,
    required this.distanceMeters,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final DangerZone zone;
  final double? distanceMeters;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final distance = distanceMeters;
    final inside = distance != null && distance <= zone.radiusMeters;
    return GlassCard(
      accent: red,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: red.withValues(alpha: .1),
                  border: Border.all(color: red.withValues(alpha: .7)),
                ),
                child: Text(
                  zone.radiusMeters >= 1000
                      ? '${(zone.radiusMeters / 1000).toStringAsFixed(1)}K'
                      : '${zone.radiusMeters.round()}',
                  style: displayFont(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: red,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${zone.radiusMeters.round()} m radius // '
                      '${distance == null
                          ? 'distance unknown'
                          : inside
                          ? 'you are inside'
                          : '${distance.round()} m away'}',
                      style: microStyle.copyWith(
                        color: inside ? red : muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete ${zone.name}',
                icon: const Icon(Icons.delete_outline, color: muted),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
