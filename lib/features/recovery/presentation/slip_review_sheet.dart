import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../zones/presentation/zone_editor_dialog.dart';
import '../../zones/domain/zone_presence.dart';
import '../../zones/presentation/zones_screen.dart';
import '../../zones/services/location_service.dart';
import '../application/recovery_provider.dart';
import '../domain/craving_entry.dart';
import '../domain/slip_review.dart';

/// A fix is only trusted as "where it happened" for a slip this recent.
const slipLocationFreshness = Duration(hours: 3);

/// Optional 3-tap review: where, who with, what set it off. Skippable with
/// one tap. Answers go onto the relapse events and feed the danger-zone
/// suggestions and the warning timing.
Future<void> showSlipReviewSheet(
  BuildContext context,
  SlipReviewRequest request,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: panel,
  builder: (_) => SlipReviewSheet(request: request),
);

class SlipReviewSheet extends ConsumerStatefulWidget {
  const SlipReviewSheet({required this.request, this.now, super.key});

  final SlipReviewRequest request;

  /// Fixed clock for tests and screenshots.
  final DateTime? now;

  @override
  ConsumerState<SlipReviewSheet> createState() => _SlipReviewSheetState();
}

class _SlipReviewSheetState extends ConsumerState<SlipReviewSheet> {
  SlipReview _review = const SlipReview();
  bool _saving = false;
  bool _marking = false;

  DateTime get _now => widget.now ?? ref.read(recoveryProvider).currentTime;

  void _pickPlace(String label, {String? zoneId}) => setState(() {
    final same = _review.cleanPlace == label;
    _review = same
        ? _review.copyWith(clearPlace: true)
        : _review.copyWith(place: label, zoneId: zoneId);
  });

  void _pickWith(String key) => setState(() {
    _review = _review.withWho == key
        ? _review.copyWith(clearWith: true)
        : _review.copyWith(withWho: key);
  });

  void _toggleTrigger(String tag) => setState(() {
    final next = [..._review.triggers];
    next.contains(tag) ? next.remove(tag) : next.add(tag);
    _review = _review.copyWith(triggers: next);
  });

  Future<void> _save() async {
    if (_saving || _review.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(recoveryProvider)
          .recordSlipReview(widget.request.eventIds, _review);
      if (!mounted) return;
      Navigator.of(context).pop();
      AppNotice.show(
        context,
        'REVIEW SAVED // YOUR WARNINGS GET MORE SPECIFIC.',
        type: AppNoticeType.success,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        AppNotice.show(
          context,
          'Could not save the review. Your slip is already logged.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  /// Turns the place the user just named into a real danger zone, using
  /// where the phone is now. Only offered for a fresh slip: a fix from hours
  /// later is not where it happened. Otherwise opens the map to place it.
  Future<void> _markAsZone(String place) async {
    if (_marking) return;
    setState(() => _marking = true);
    try {
      final fresh =
          _now.difference(widget.request.occurredAt) <= slipLocationFreshness;
      final location = ref.read(locationServiceProvider);
      LocationFix? fix;
      if (fresh) {
        final access = await location.requestForeground();
        if (access == LocationAccess.whileInUse ||
            access == LocationAccess.always) {
          fix = await location.currentFix();
        }
      }
      if (!mounted) return;
      if (fix == null) {
        AppNotice.show(
          context,
          fresh
              ? 'No location fix. Place it on the map instead.'
              : 'That was a while ago. Place it on the map.',
          type: AppNoticeType.info,
        );
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ZonesScreen()));
        return;
      }
      final draft = await showZoneEditorDialog(
        context,
        latitude: fix.latitude,
        longitude: fix.longitude,
        initialName: place,
      );
      if (draft == null || !mounted) return;
      final zone = await ref
          .read(recoveryProvider)
          .addZone(
            name: draft.name,
            latitude: fix.latitude,
            longitude: fix.longitude,
            radiusMeters: draft.radiusMeters,
          );
      if (!mounted) return;
      setState(() {
        _review = _review.copyWith(place: zone.name, zoneId: zone.id);
      });
      AppNotice.show(
        context,
        'DANGER ZONE SAVED // ${zone.name.toUpperCase()}',
        type: AppNoticeType.success,
      );
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          error is StateError
              ? error.message
              : 'The danger zone could not be saved.',
          type: AppNoticeType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Widget _chip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    Color color = cyan,
    Key? key,
    IconData? icon,
  }) => ChoiceChip(
    key: key,
    avatar: icon == null ? null : Icon(icon, size: 16, color: color),
    label: Text(
      label,
      style: TextStyle(fontSize: 12, color: selected ? Colors.white : null),
    ),
    selected: selected,
    selectedColor: color.withValues(alpha: .25),
    side: BorderSide(color: selected ? color : muted.withValues(alpha: .45)),
    onSelected: (_) => onTap(),
  );

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final place = _review.cleanPlace;
    final isZone = _review.zoneId != null;
    // Slips already reviewed at this place, plus this one.
    final seen = place == null ? 0 : slipsAtPlace(recovery.events, place);
    final offerZone = place != null && !isZone && place != 'Outside';
    final onlyThis = widget.request.eventIds.length;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          key: const ValueKey('slip-review'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The chips scroll; SAVE and SKIP stay pinned and reachable.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'QUICK REVIEW',
                      style: eyebrowStyle.copyWith(color: cyan),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      onlyThis > 1
                          ? 'Three taps for this stretch. Skip any time.'
                          : 'Three taps, all optional. Skip any time.',
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'It helps your warnings fit when and where this really '
                      'happens. Nothing here is shared.',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '1 // WHERE',
                      style: eyebrowStyle.copyWith(color: magenta),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final zone in recovery.zones)
                          _chip(
                            zone.name,
                            key: ValueKey('review-zone-${zone.id}'),
                            icon: Icons.place,
                            color: red,
                            selected: _review.zoneId == zone.id,
                            onTap: () => _pickPlace(zone.name, zoneId: zone.id),
                          ),
                        for (final label in slipPlaceOptions)
                          if (!recovery.zones.any(
                            (z) => z.name.toLowerCase() == label.toLowerCase(),
                          ))
                            _chip(
                              label,
                              key: ValueKey('review-place-$label'),
                              color: magenta,
                              selected: place == label && !isZone,
                              onTap: () => _pickPlace(label),
                            ),
                      ],
                    ),
                    if (offerZone)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          key: const ValueKey('review-zone-offer'),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: red.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: red.withValues(alpha: .4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  seen >= 1
                                      ? 'This would be slip ${seen + 1} at $place. '
                                            'Want a heads-up when you get near?'
                                      : 'Want a heads-up when you get near $place?',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              TextButton(
                                key: const ValueKey('review-mark-zone'),
                                onPressed: _marking
                                    ? null
                                    : () => _markAsZone(place),
                                child: const Text('MAKE IT A ZONE'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      '2 // WHO WITH',
                      style: eyebrowStyle.copyWith(color: magenta),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in slipWithOptions.entries)
                          _chip(
                            e.value,
                            key: ValueKey('review-with-${e.key}'),
                            color: purple,
                            selected: _review.withWho == e.key,
                            onTap: () => _pickWith(e.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '3 // WHAT SET IT OFF',
                      style: eyebrowStyle.copyWith(color: magenta),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in recoveryTriggerOptions)
                          _chip(
                            tag,
                            key: ValueKey('review-trigger-$tag'),
                            color: toxic,
                            selected: _review.triggers.contains(tag),
                            onTap: () => _toggleTrigger(tag),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              key: const ValueKey('review-save'),
              onPressed: _review.isEmpty || _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('SAVE REVIEW'),
            ),
            TextButton(
              key: const ValueKey('review-skip'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('SKIP'),
            ),
          ],
        ),
      ),
    );
  }
}
