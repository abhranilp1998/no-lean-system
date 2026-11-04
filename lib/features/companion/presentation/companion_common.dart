import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_controller.dart';
import '../../recovery/domain/recovery_event.dart';
import '../../settings/services/trusted_contact_service.dart';
import '../../withdrawal/domain/withdrawal_personal.dart';
import '../domain/companion_engine.dart';
import '../domain/companion_messages.dart';
import '../domain/companion_state.dart';
import '../domain/substance_safety.dart';

/// Last relapse within 72 h, or a slip note within 72 h.
/// A use in the last 72 h that came after at least 3 clean days (a lapse
/// after progress), or a slip the user logged in the slip flow. The last use
/// of a daily-use run (someone who has just stopped) is not a slip.
bool recentSlip(RecoveryController r, DateTime now) {
  bool near(DateTime t) => now.difference(t) < const Duration(hours: 72);
  if (r.companion.slips.any((s) => near(s.at))) return true;
  final uses =
      r.events
          .where((e) => e.type == RecoveryEventType.relapse)
          .map((e) => e.timestamp)
          .toList()
        ..sort();
  for (var i = uses.length - 1; i >= 0 && near(uses[i]); i--) {
    if (i == 0) return false;
    if (uses[i].difference(uses[i - 1]) >= const Duration(hours: 72)) {
      return true;
    }
  }
  return false;
}

/// Hours until symptoms usually start easing, from the user's own course.
int? easeInHours(RecoveryController r, DateTime now) {
  final plan = buildPlan(
    events: r.events,
    cleanSince: r.lastDose,
    now: now,
    riskWindow: r.riskWindow,
  );
  final left = plan.course.peakEndH - plan.sinceLastUse.inHours;
  return left > 0 ? left : null;
}

CompanionContext contextFor(
  RecoveryController r, {
  required DateTime now,
  Duration? since,
  Set<String> symptoms = const {},
  String? mood,
  int craving = 0,
  String name = '',
  String contact = '',
}) => CompanionContext(
  since: since ?? r.cleanDuration,
  now: now,
  symptoms: symptoms,
  mood: mood,
  craving: craving,
  recentSlip: recentSlip(r, now),
  name: name,
  bestDays: r.longestStreak,
  saved: r.dailySpend > 0 && r.moneySaved >= 1 ? money(r.moneySaved) : '',
  contact: contact,
  easeInHours: since == null ? easeInHours(r, now) : null,
);

final trustedContactProvider = FutureProvider.autoDispose<TrustedContact?>((
  ref,
) async {
  try {
    return await ref.read(trustedContactServiceProvider).getContact();
  } catch (_) {
    return null;
  }
});

/// A message with "helps / not for me" buttons feeding the weighting.
class MessageCard extends StatelessWidget {
  const MessageCard({
    required this.message,
    required this.text,
    required this.onRate,
    this.accent = cyan,
    super.key,
  });
  final CompanionMessage message;
  final String text;
  final void Function(bool helpful) onRate;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassCard(
      accent: accent,
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontSize: 15, height: 1.35)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => onRate(true),
                icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
                label: const Text('Helps'),
              ),
              TextButton(
                onPressed: () => onRate(false),
                child: const Text('Not for me'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class SafetyCard extends StatelessWidget {
  const SafetyCard(this.note, {this.urgent = false, super.key});
  final SafetyNote note;
  final bool urgent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GlassCard(
      accent: urgent ? red : magenta,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            urgent ? Icons.local_hospital : Icons.info_outline,
            color: urgent ? red : magenta,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(note.body, style: const TextStyle(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// "When to get urgent help": quiet, expandable unless [open].
class RedFlagsTile extends StatelessWidget {
  const RedFlagsTile({this.open = false, super.key});
  final bool open;

  @override
  Widget build(BuildContext context) => open
      ? const SafetyCard(redFlagNote, urgent: true)
      : ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.local_hospital_outlined, color: red),
          title: const Text('When to get urgent help'),
          children: const [SafetyCard(redFlagNote, urgent: true)],
        );
}

/// Opens the phone's SMS app with [text]; no network use by the app.
Future<bool> sendText(String text, {String? phone}) async {
  try {
    return await launchUrl(
      Uri(scheme: 'sms', path: phone ?? '', queryParameters: {'body': text}),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

String fillReachOut(String text, CompanionContext c) =>
    text.replaceAll('{hours}', '${c.since.inHours}');

/// Reach-out sheet: pick, edit and send a ready text to the trusted contact.
Future<void> showReachOutSheet(
  BuildContext context,
  WidgetRef ref,
  RecoveryController recovery,
) async {
  final contact = await ref.read(trustedContactProvider.future);
  if (!context.mounted) return;
  final c = contextFor(recovery, now: DateTime.now());
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final texts = recovery.companion.reachOutTexts;
        Future<void> edit(int? index) async {
          final ctrl = TextEditingController(
            text: index == null ? '' : texts[index],
          );
          final v = await showDialog<String>(
            context: ctx,
            builder: (d) => AlertDialog(
              title: Text(index == null ? 'New message' : 'Edit message'),
              content: TextField(
                controller: ctrl,
                maxLines: 4,
                maxLength: 300,
                autofocus: true,
              ),
              actions: [
                if (index != null)
                  TextButton(
                    onPressed: () => Navigator.pop(d, ''),
                    child: const Text('Delete'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(d, ctrl.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (v == null) return;
          final next = List.of(texts);
          if (index == null) {
            if (v.isEmpty) return;
            next.add(v);
          } else if (v.isEmpty) {
            next.removeAt(index);
          } else {
            next[index] = v;
          }
          await recovery.updateCompanion(
            (s) => s.copyWith(
              reachOutTexts: next.isEmpty ? defaultReachOutTexts : next,
            ),
          );
          setSheet(() {});
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact == null ? 'Reach out' : 'Message ${contact.name}',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  contact == null
                      ? 'No trusted contact saved yet (Settings > SOS contact). '
                            'You can still pick who to send it to.'
                      : 'Tap to open your messages app. Long-press to edit.',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < texts.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.sms_outlined, color: cyan),
                          title: Text(fillReachOut(texts[i], c)),
                          trailing: IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => edit(i),
                          ),
                          onLongPress: () => edit(i),
                          onTap: () async {
                            final ok = await sendText(
                              fillReachOut(texts[i], c),
                              phone: contact?.phone,
                            );
                            if (!ok && ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('No messages app found.'),
                                ),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => edit(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add your own'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
