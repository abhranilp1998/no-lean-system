import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/services/save_action.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/presentation/relapse_auth_dialog.dart';
import '../domain/danger_zone.dart';
import '../domain/zone_presence.dart';
import '../services/location_service.dart';
import '../services/map_tiles.dart';
import 'map_style.dart';
import 'offline_grid_layer.dart';
import 'zone_map_markers.dart';
import 'zone_editor_dialog.dart';
import 'zone_monitoring_panel.dart';
import '../../timeline/presentation/timeline_screen.dart';
import '../../timeline/domain/history_projection.dart';
import '../services/zone_test_trigger.dart';

class ZonesScreen extends ConsumerStatefulWidget {
  const ZonesScreen({super.key});

  @override
  ConsumerState<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends ConsumerState<ZonesScreen> {
  final _map = MapController();
  LocationFix? _me;
  bool _locating = false;
  bool _tilesFailing = false;
  bool _tilesOkScheduled = false;

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (!_tilesFailing && mounted) setState(() => _tilesFailing = true);
  }

  Widget _tileBuilder(BuildContext context, Widget tile, TileImage image) {
    if (_tilesFailing &&
        !_tilesOkScheduled &&
        image.loadFinishedAt != null &&
        !image.loadError) {
      _tilesOkScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tilesOkScheduled = false;
        if (mounted) setState(() => _tilesFailing = false);
      });
    }
    return neonTileBuilder(context, tile, image);
  }

  void _zoomBy(double delta) {
    final camera = _map.camera;
    _map.move(camera.center, (camera.zoom + delta).clamp(3, 19).toDouble());
  }

  void _fitZones() {
    final zones = ref.read(recoveryProvider).zones;
    if (zones.isEmpty) return;
    if (zones.length == 1) {
      _map.move(LatLng(zones.single.latitude, zones.single.longitude), 15);
      return;
    }
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [
          for (final zone in zones) LatLng(zone.latitude, zone.longitude),
        ],
        padding: const EdgeInsets.all(48),
        maxZoom: 16,
      ),
    );
  }

  Future<void> _openOsmCopyright() async {
    try {
      await launchUrl(
        Uri.parse(osmCopyrightUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Attribution stays visible even if no browser is available.
    }
  }

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

  /// Test: saves a 150 m zone at the current GPS fix and fires the real
  /// zone-entry path (alert screen; native lock if enabled in App Lock).
  Future<void> _testHere() async {
    final fix = await _locate();
    if (fix == null || !mounted) return;
    final location = ref.read(locationServiceProvider);
    try {
      final zone = await ref
          .read(recoveryProvider)
          .addZone(
            name: testZoneName,
            latitude: fix.latitude,
            longitude: fix.longitude,
            radiusMeters: testZoneRadiusMeters,
          );
      if (!mounted) return;
      AppNotice.show(
        context,
        'TEST ZONE ARMED // 150 m around you. Triggering entry now.',
        type: AppNoticeType.success,
      );
      ZoneTestTrigger.instance.fire(zone);
      // Background alerts/locking need "Allow all the time" location.
      unawaited(location.requestBackground().then((_) {}, onError: (_) {}));
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          error is StateError ? error.message : 'Test zone could not be saved.',
          type: AppNoticeType.error,
        );
      }
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
    // With street tiles off the provider is never created: no network at all.
    final tiles = recovery.streetTiles
        ? ref.watch(mapTileProviderProvider).valueOrNull
        : null;
    final zones = recovery.zones;
    final me = _me;
    final mapMode = !recovery.streetTiles
        ? MapMode.tilesOff
        : tiles == null
        ? MapMode.grid
        : _tilesFailing
        ? MapMode.fallback
        : MapMode.street;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            key: const ValueKey('zones-test-here'),
            tooltip: 'Test: mark my current location as danger zone',
            onPressed: _locating ? null : _testHere,
            icon: const Icon(Icons.science_outlined),
          ),
          IconButton(
            key: const ValueKey('zones-location-history'),
            tooltip: 'Location history',
            onPressed: () => TimelineScreen.openPage(
              context,
              category: HistoryCategory.location,
            ),
            icon: const Icon(Icons.history),
          ),
        ],
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
            Text(
              'MARK THE PLACES WHERE BUYING HAPPENS',
              style: eyebrowStyle.copyWith(color: red),
            ),
            const SizedBox(height: 6),
            const Text(
              'Long-press the map to drop a pin, or stand there and tap PIN HERE. Street tiles come from OpenStreetMap and are cached on this device once viewed; turn them off with the globe button for no network requests. With no network the grid takes over: zones, pins and alerts never need internet, and your zones never leave the phone.',
              style: TextStyle(color: muted, fontSize: 11.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cyan.withValues(alpha: .35)),
                boxShadow: [
                  BoxShadow(color: cyan.withValues(alpha: .14), blurRadius: 22),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: SizedBox(
                  height: 360,
                  child: Stack(
                    children: [
                      FlutterMap(
                        key: const ValueKey('zones-map'),
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: _initialCenter,
                          initialZoom: zones.isEmpty ? 3 : 15,
                          minZoom: 3,
                          maxZoom: 19,
                          backgroundColor: ink,
                          onLongPress: (_, point) =>
                              _createAt(point.latitude, point.longitude),
                        ),
                        children: [
                          const OfflineGridLayer(showScaleBar: false),
                          if (tiles != null)
                            TileLayer(
                              key: const ValueKey('osm-tiles'),
                              urlTemplate: osmTileUrl,
                              userAgentPackageName: mapUserAgentPackage,
                              maxNativeZoom: osmMaxNativeZoom,
                              tileProvider: tiles,
                              tileBuilder: _tileBuilder,
                              errorTileCallback: _onTileError,
                              evictErrorTileStrategy: EvictErrorTileStrategy
                                  .notVisibleRespectMargin,
                            ),
                          if (tiles != null)
                            const OfflineGridLayer(
                              background: false,
                              showScaleBar: false,
                              lineOpacity: .45,
                            ),
                          CircleLayer(
                            circles: [
                              for (final zone in zones)
                                ...zoneCircles(
                                  LatLng(zone.latitude, zone.longitude),
                                  zone.radiusMeters,
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
                                  width: ZonePinMarker.width,
                                  height: ZonePinMarker.height,
                                  alignment: ZonePinMarker.alignment,
                                  child: ZonePinMarker(label: zone.name),
                                ),
                              if (me != null)
                                Marker(
                                  point: LatLng(me.latitude, me.longitude),
                                  width: 28,
                                  height: 28,
                                  child: const MyLocationMarker(),
                                ),
                            ],
                          ),
                          const OfflineGridLayer(
                            background: false,
                            lineOpacity: 0,
                          ),
                          if (tiles != null)
                            OsmAttribution(onTap: _openOsmCopyright),
                        ],
                      ),
                      const Positioned.fill(child: MapHudFrame()),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: MapStatusChip(mode: mapMode),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Column(
                          children: [
                            MapControlButton(
                              key: const ValueKey('map-zoom-in'),
                              icon: Icons.add,
                              tooltip: 'Zoom in',
                              onPressed: () => _zoomBy(1),
                            ),
                            const SizedBox(height: 6),
                            MapControlButton(
                              key: const ValueKey('map-zoom-out'),
                              icon: Icons.remove,
                              tooltip: 'Zoom out',
                              onPressed: () => _zoomBy(-1),
                            ),
                            const SizedBox(height: 6),
                            MapControlButton(
                              key: const ValueKey('map-tiles-toggle'),
                              icon: recovery.streetTiles
                                  ? Icons.public
                                  : Icons.public_off,
                              tooltip: recovery.streetTiles
                                  ? 'Turn street tiles off'
                                  : 'Turn street tiles on',
                              color: recovery.streetTiles ? cyan : toxic,
                              onPressed: () => saveAction(
                                context,
                                () => ref
                                    .read(recoveryProvider)
                                    .setStreetTiles(!recovery.streetTiles),
                              ),
                            ),
                            const SizedBox(height: 6),
                            MapControlButton(
                              key: const ValueKey('map-fit-zones'),
                              icon: Icons.center_focus_strong,
                              tooltip: 'Show all zones',
                              color: red,
                              onPressed: zones.isEmpty ? null : _fitZones,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: HudActionButton(
                    key: const ValueKey('zones-locate'),
                    label: _locating ? 'LOCATING…' : 'LOCATE ME',
                    icon: Icons.my_location,
                    color: cyan,
                    onPressed: _locating ? null : _locate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HudActionButton(
                    key: const ValueKey('zones-pin-here'),
                    label: 'PIN HERE',
                    icon: Icons.add_location_alt,
                    color: magenta,
                    filled: true,
                    onPressed: _locating
                        ? null
                        : () async {
                            final fix = _me ?? await _locate();
                            if (fix != null) {
                              await _createAt(fix.latitude, fix.longitude);
                            }
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Text('YOUR ZONES', style: eyebrowStyle.copyWith(color: red)),
                const Spacer(),
                StatusPill(
                  label: '${zones.length}/${DangerZone.maxZones} ARMED',
                  color: zones.isEmpty ? muted : red,
                ),
              ],
            ),
            const SizedBox(height: 10),
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
                child: ZoneListCard(
                  key: ValueKey('zone-${zone.id}'),
                  zone: zone,
                  distanceMeters: me == null
                      ? null
                      : zone.distanceTo(me.latitude, me.longitude),
                  onTap: () {
                    _map.move(LatLng(zone.latitude, zone.longitude), 15);
                    _edit(zone);
                  },
                  onDelete: () => _delete(zone),
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
