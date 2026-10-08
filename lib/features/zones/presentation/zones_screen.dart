import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/presentation/relapse_auth_dialog.dart';
import '../domain/danger_zone.dart';
import '../domain/zone_presence.dart';
import '../services/location_service.dart';
import 'offline_grid_layer.dart';
import 'zone_editor_dialog.dart';
import 'zone_monitoring_panel.dart';

class ZonesScreen extends ConsumerStatefulWidget {
  const ZonesScreen({super.key});

  @override
  ConsumerState<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends ConsumerState<ZonesScreen> {
  final _map = MapController();
  LocationFix? _me;
  bool _locating = false;

  LatLng get _initialCenter {
    final zones = ref.read(recoveryProvider).zones;
    if (zones.isNotEmpty) {
      return LatLng(zones.first.latitude, zones.first.longitude);
    }
    return const LatLng(20, 0);
  }

  Future<LocationFix?> _locate() async {
    if (_locating) return null;
    setState(() => _locating = true);
    final location = ref.read(locationServiceProvider);
    try {
      final access = await location.requestForeground();
      if (!mounted) return null;
      if (access != LocationAccess.whileInUse &&
          access != LocationAccess.always) {
        AppNotice.show(context, switch (access) {
          LocationAccess.serviceDisabled =>
            'Location is switched off. Turn it on, or long-press the map to place a pin manually.',
          LocationAccess.deniedForever =>
            'Location is blocked for NO LEAN. Allow it in system settings, or place pins manually.',
          _ =>
            'Location was not granted. You can still long-press the map to place a pin.',
        }, type: AppNoticeType.warning);
        return null;
      }
      final fix = await location.currentFix();
      if (!mounted) return null;
      if (fix == null) {
        AppNotice.show(
          context,
          'No location fix yet. Try again outdoors or near a window.',
          type: AppNoticeType.warning,
        );
        return null;
      }
      setState(() => _me = fix);
      _map.move(LatLng(fix.latitude, fix.longitude), 16);
      return fix;
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _createAt(double latitude, double longitude) async {
    final draft = await showZoneEditorDialog(
      context,
      latitude: latitude,
      longitude: longitude,
    );
    if (draft == null || !mounted) return;
    try {
      await ref
          .read(recoveryProvider)
          .addZone(
            name: draft.name,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: draft.radiusMeters,
          );
      if (mounted) {
        AppNotice.show(
          context,
          'ZONE ARMED // ${draft.name.toUpperCase()}',
          type: AppNoticeType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          error is StateError
              ? error.message
              : 'Zone could not be saved. Nothing was changed.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _edit(DangerZone zone) async {
    final draft = await showZoneEditorDialog(
      context,
      latitude: zone.latitude,
      longitude: zone.longitude,
      existing: zone,
    );
    if (draft == null || !mounted) return;
    await _protected(
      (pin) => ref
          .read(recoveryProvider)
          .updateZone(
            zone.id,
            name: draft.name,
            radiusMeters: draft.radiusMeters,
            pin: pin,
            tryBiometrics: pin == null,
          ),
      actionLabel: 'SHRINK ZONE',
      success: 'ZONE UPDATED.',
    );
  }

  Future<void> _delete(DangerZone zone) async {
    await _protected(
      (pin) => ref
          .read(recoveryProvider)
          .deleteZone(zone.id, pin: pin, tryBiometrics: pin == null),
      actionLabel: 'DELETE ZONE',
      success: 'ZONE REMOVED // ${zone.name.toUpperCase()}',
    );
  }

  Future<void> _protected(
    Future<ProtectedActionResult> Function(String? pin) action, {
    required String actionLabel,
    required String success,
  }) async {
    try {
      var result = await action(null);
      if (result == ProtectedActionResult.authenticationRequired && mounted) {
        final pin = await showRelapsePinDialog(
          context,
          actionLabel: actionLabel,
        );
        if (pin == null) return;
        result = await action(pin);
      }
      if (!mounted) return;
      AppNotice.show(
        context,
        result == ProtectedActionResult.completed
            ? success
            : '${result.failureMessage} ZONE UNCHANGED.',
        type: result == ProtectedActionResult.completed
            ? AppNoticeType.info
            : AppNoticeType.error,
      );
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'Zone could not be saved. Nothing was changed.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final zones = recovery.zones;
    final me = _me;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'DANGER ZONES',
          style: displayFont(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(label: 'OFFLINE MAP // NO TILES', color: cyan),
            ),
            const SizedBox(height: 10),
            const Text(
              'No map data is downloaded. Tap LOCATE ME to centre the grid on your position, then long-press to drop a pin. Pins are relative to where you are, so mark places while you stand near them or place them by distance using the scale bar.',
              style: TextStyle(color: muted, fontSize: 11.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 320,
                child: FlutterMap(
                  key: const ValueKey('zones-map'),
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _initialCenter,
                    initialZoom: zones.isEmpty ? 3 : 15,
                    backgroundColor: ink,
                    onLongPress: (_, point) =>
                        _createAt(point.latitude, point.longitude),
                  ),
                  children: [
                    const OfflineGridLayer(),
                    CircleLayer(
                      circles: [
                        for (final zone in zones)
                          CircleMarker(
                            point: LatLng(zone.latitude, zone.longitude),
                            radius: zone.radiusMeters,
                            useRadiusInMeter: true,
                            color: red.withValues(alpha: .16),
                            borderColor: red,
                            borderStrokeWidth: 2,
                          ),
                        if (me != null)
                          CircleMarker(
                            point: LatLng(me.latitude, me.longitude),
                            radius: me.accuracyMeters,
                            useRadiusInMeter: true,
                            color: cyan.withValues(alpha: .1),
                            borderColor: cyan.withValues(alpha: .5),
                            borderStrokeWidth: 1,
                          ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        for (final zone in zones)
                          Marker(
                            point: LatLng(zone.latitude, zone.longitude),
                            width: 30,
                            height: 30,
                            child: const Icon(
                              Icons.dangerous,
                              color: red,
                              size: 26,
                            ),
                          ),
                        if (me != null)
                          Marker(
                            point: LatLng(me.latitude, me.longitude),
                            width: 22,
                            height: 22,
                            child: const Icon(
                              Icons.my_location,
                              color: cyan,
                              size: 20,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('zones-locate'),
                    onPressed: _locating ? null : _locate,
                    icon: const Icon(Icons.my_location, color: cyan),
                    label: Text(_locating ? 'LOCATING…' : 'LOCATE ME'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('zones-pin-here'),
                    style: FilledButton.styleFrom(backgroundColor: magenta),
                    onPressed: _locating
                        ? null
                        : () async {
                            final fix = _me ?? await _locate();
                            if (fix != null) {
                              await _createAt(fix.latitude, fix.longitude);
                            }
                          },
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('PIN HERE'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'YOUR ZONES // ${zones.length}/${DangerZone.maxZones}',
              style: eyebrowStyle.copyWith(color: red),
            ),
            const SizedBox(height: 8),
            if (zones.isEmpty)
              const GlassCard(
                accent: muted,
                child: Text(
                  'No zones yet. Mark the places where buying happens: the pharmacy, the street corner, the friend\'s flat.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.45),
                ),
              ),
            for (final zone in zones)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  accent: red,
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  child: ListTile(
                    key: ValueKey('zone-${zone.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.dangerous, color: red),
                    title: Text(zone.name),
                    subtitle: Text(
                      '${zone.radiusMeters.round()} m // '
                      '${me == null ? 'distance unknown' : '${zone.distanceTo(me.latitude, me.longitude).round()} m away'}',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    onTap: () {
                      _map.move(LatLng(zone.latitude, zone.longitude), 15);
                      _edit(zone);
                    },
                    trailing: IconButton(
                      tooltip: 'Delete ${zone.name}',
                      icon: const Icon(Icons.delete_outline, color: muted),
                      onPressed: () => _delete(zone),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const ZoneMonitoringPanel(),
          ],
        ),
      ),
    );
  }
}
