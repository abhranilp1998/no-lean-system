import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/tab_layout.dart';
import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/glow_button.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../recovery/domain/if_then_plan.dart';
import '../../recovery/domain/trigger_tags.dart';

/// Write, edit and delete "If I'm at X or feel Y, then I will Z" plans.
/// Everything stays on the phone (and in the user's own backup).
class IfThenPlansScreen extends ConsumerStatefulWidget {
  const IfThenPlansScreen({this.suggestedIf, super.key});

  /// Opens the editor straight away with this situation filled in (from a
  /// pattern the user's own tags showed).
  final String? suggestedIf;

  static Future<void> open(BuildContext context, {String? suggestedIf}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => IfThenPlansScreen(suggestedIf: suggestedIf),
        ),
      );

  @override
  ConsumerState<IfThenPlansScreen> createState() => _IfThenPlansScreenState();
}

class _IfThenPlansScreenState extends ConsumerState<IfThenPlansScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.suggestedIf != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _edit(null, suggestedIf: widget.suggestedIf);
      });
    }
  }

  Future<void> _edit(IfThenPlan? plan, {String? suggestedIf}) async {
    final result = await showModalBottomSheet<_PlanDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: panel,
      builder: (_) => IfThenPlanEditor(plan: plan, suggestedIf: suggestedIf),
    );
    if (result == null || !mounted) return;
    final recovery = ref.read(recoveryProvider);
    try {
      if (plan == null) {
        await recovery.addIfThenPlan(
          ifText: result.ifText,
          thenText: result.thenText,
          surfaces: result.surfaces,
          zoneId: result.zoneId,
          mood: result.mood,
        );
      } else {
        await recovery.updateIfThenPlan(
          plan.copyWith(
            ifText: result.ifText,
            thenText: result.thenText,
            surfaces: result.surfaces,
            zoneId: result.zoneId,
            clearZone: result.zoneId == null,
            mood: result.mood,
            clearMood: result.mood == null,
          ),
        );
      }
      if (mounted) {
        AppNotice.show(
          context,
          'PLAN SAVED // IT SHOWS UP WHEN YOU NEED IT.',
          type: AppNoticeType.success,
        );
      }
    } catch (error) {
      if (mounted) {
        AppNotice.show(
          context,
          error is StateError ? error.message : 'Could not save the plan.',
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _delete(IfThenPlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this plan?'),
        content: Text(plan.sentence),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('KEEP IT'),
          ),
          TextButton(
            key: const ValueKey('plan-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(recoveryProvider).deleteIfThenPlan(plan.id);
    }
  }

  static String _where(IfThenPlan plan, Map<String, String> zoneNames) {
    if (plan.mood != null) {
      return 'when you log a craving and feel '
          '${triggerMoodOptions[plan.mood]?.toLowerCase() ?? plan.mood}';
    }
    final parts = <String>[
      if (plan.surfaces.contains(PlanSurface.zone))
        plan.zoneId == null
            ? 'any danger zone'
            : zoneNames[plan.zoneId] ?? 'a danger zone',
      if (plan.surfaces.contains(PlanSurface.window)) 'risk window / peak',
      if (plan.surfaces.contains(PlanSurface.craving)) 'when you log a craving',
    ];
    return parts.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final recovery = ref.watch(recoveryProvider);
    final plans = recovery.ifThenPlans;
    final zoneNames = {for (final z in recovery.zones) z.id: z.name};
    return Scaffold(
      appBar: AppBar(title: const Text('If-then plans')),
      body: SafeArea(
        child: TabListView(
          children: [
            const Text(
              'Decide now, while you\'re steady. When the moment comes, the '
              'choice is already made.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your words, kept on this phone. They appear when you enter a '
              'danger zone, in your risk window or around your usual peak, '
              'and when you log a craving.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 16),
            GlowButton(
              key: const ValueKey('plan-add'),
              label: 'WRITE A PLAN',
              icon: Icons.add,
              color: toxic,
              onTap: () => _edit(null),
            ),
            const SizedBox(height: 16),
            if (plans.isEmpty)
              GlassCard(
                accent: muted,
                child: const Text(
                  'No plans yet. One is enough to start: "If I\'m bored on '
                  'the way home, then I will call my brother."',
                  key: ValueKey('plans-empty'),
                  style: TextStyle(color: muted, fontSize: 12, height: 1.45),
                ),
              ),
            for (final plan in plans)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  accent: toxic,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.sentence,
                        key: ValueKey('plan-${plan.id}'),
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'SHOWS: ${_where(plan, zoneNames).toUpperCase()}',
                        style: microStyle,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            key: ValueKey('plan-edit-${plan.id}'),
                            onPressed: () => _edit(plan),
                            child: const Text('EDIT'),
                          ),
                          TextButton(
                            key: ValueKey('plan-delete-${plan.id}'),
                            onPressed: () => _delete(plan),
                            child: const Text('DELETE'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanDraft {
  const _PlanDraft({
    required this.ifText,
    required this.thenText,
    required this.surfaces,
    this.zoneId,
    this.mood,
  });

  final String ifText;
  final String thenText;
  final Set<PlanSurface> surfaces;
  final String? zoneId;
  final String? mood;
}

/// Starters the user can tap and then rewrite in their own words.
const planStarters = <(String, String)>[
  ("I'm bored on the way home", 'walk the long way and call my brother'),
  ('I feel the craving building', 'drink a glass of water and start SOS'),
  ("I'm near the shop", 'cross the road and keep walking for ten minutes'),
];

class IfThenPlanEditor extends StatefulWidget {
  const IfThenPlanEditor({this.plan, this.suggestedIf, super.key});

  final IfThenPlan? plan;
  final String? suggestedIf;

  @override
  State<IfThenPlanEditor> createState() => _IfThenPlanEditorState();
}

class _IfThenPlanEditorState extends State<IfThenPlanEditor> {
  late final TextEditingController _if = TextEditingController(
    text: widget.plan?.ifText ?? widget.suggestedIf ?? '',
  );
  late final TextEditingController _then = TextEditingController(
    text: widget.plan?.thenText ?? '',
  );
  late final Set<PlanSurface> _surfaces = {
    ...widget.plan?.surfaces ?? IfThenPlan.defaultSurfaces,
  };
  late String? _mood = widget.plan?.mood;
  late String? _zoneId = widget.plan?.zoneId;
  String? _error;

  @override
  void dispose() {
    _if.dispose();
    _then.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final ifText = IfThenPlan.validateIf(_if.text);
      final thenText = IfThenPlan.validateThen(_then.text);
      final mood = _surfaces.contains(PlanSurface.craving) ? _mood : null;
      Navigator.pop(
        context,
        _PlanDraft(
          ifText: ifText,
          thenText: thenText,
          // A mood plan shows where the mood is tagged: the craving sheet.
          surfaces: mood != null
              ? {PlanSurface.craving}
              : _surfaces.isEmpty
              ? IfThenPlan.defaultSurfaces
              : _surfaces,
          zoneId: mood == null && _surfaces.contains(PlanSurface.zone)
              ? _zoneId
              : null,
          mood: mood,
        ),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Widget _surfaceChip(PlanSurface surface, String label) => FilterChip(
    key: ValueKey('plan-surface-${surface.name}'),
    label: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: _surfaces.contains(surface) ? Colors.white : null,
      ),
    ),
    selected: _surfaces.contains(surface),
    selectedColor: toxic.withValues(alpha: .22),
    onSelected: (on) => setState(() {
      on ? _surfaces.add(surface) : _surfaces.remove(surface);
    }),
  );

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final zones = ref.watch(recoveryProvider).zones;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            key: const ValueKey('plan-editor'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.plan == null ? 'NEW PLAN' : 'EDIT PLAN',
                        style: eyebrowStyle.copyWith(color: toxic),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('plan-if'),
                        controller: _if,
                        maxLength: IfThenPlan.maxIfLength,
                        maxLines: 2,
                        textInputAction: TextInputAction.next,
                        scrollPadding: KeyboardSafeScroll.fieldScrollPadding,
                        decoration: const InputDecoration(
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixText: 'If ',
                          labelText: "I'm at... / I feel...",
                          hintText: "I'm bored on the way home",
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('plan-then'),
                        controller: _then,
                        maxLength: IfThenPlan.maxThenLength,
                        maxLines: 2,
                        scrollPadding: KeyboardSafeScroll.fieldScrollPadding,
                        decoration: const InputDecoration(
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixText: 'then I will ',
                          labelText: 'One small thing I can do',
                          hintText: 'walk the long way and call my brother',
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _error!,
                            key: const ValueKey('plan-error'),
                            style: const TextStyle(color: red, fontSize: 12),
                          ),
                        ),
                      if (widget.plan == null &&
                          _if.text.isEmpty &&
                          _then.text.isEmpty) ...[
                        const SizedBox(height: 10),
                        const Text('NEED AN IDEA?', style: microStyle),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (i, starter) in planStarters.indexed)
                              ActionChip(
                                key: ValueKey('plan-starter-$i'),
                                label: Text(
                                  'If ${starter.$1}...',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () => setState(() {
                                  _if.text = starter.$1;
                                  _then.text = starter.$2;
                                }),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text('SHOW IT', style: microStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _surfaceChip(PlanSurface.zone, 'In a danger zone'),
                          _surfaceChip(
                            PlanSurface.window,
                            'Risk window / usual peak',
                          ),
                          _surfaceChip(
                            PlanSurface.craving,
                            'When I log a craving',
                          ),
                        ],
                      ),
                      if (_surfaces.contains(PlanSurface.zone) &&
                          zones.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'ONLY FOR ONE ZONE? (OPTIONAL)',
                          style: microStyle,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              key: const ValueKey('plan-zone-any'),
                              label: const Text(
                                'Any zone',
                                style: TextStyle(fontSize: 12),
                              ),
                              selected: _zoneId == null,
                              onSelected: (_) => setState(() => _zoneId = null),
                            ),
                            for (final zone in zones)
                              ChoiceChip(
                                key: ValueKey('plan-zone-${zone.id}'),
                                label: Text(
                                  zone.name,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                selected: _zoneId == zone.id,
                                onSelected: (_) =>
                                    setState(() => _zoneId = zone.id),
                              ),
                          ],
                        ),
                      ],
                      if (_surfaces.contains(PlanSurface.craving)) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'ONLY WHEN I TAG THIS MOOD? (OPTIONAL, SHOWS WITH THE CRAVING TAGS)',
                          style: microStyle,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in triggerMoodOptions.entries)
                              ChoiceChip(
                                key: ValueKey('plan-mood-${entry.key}'),
                                label: Text(
                                  entry.value,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                selected: _mood == entry.key,
                                onSelected: (_) => setState(
                                  () => _mood = _mood == entry.key
                                      ? null
                                      : entry.key,
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              FilledButton(
                key: const ValueKey('plan-save'),
                onPressed: _save,
                style: FilledButton.styleFrom(backgroundColor: toxic),
                child: const Text(
                  'SAVE PLAN',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
