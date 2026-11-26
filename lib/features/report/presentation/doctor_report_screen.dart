import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/app_notice.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_card.dart';
import '../../recovery/application/recovery_provider.dart';
import '../../withdrawal/data/symptom_checkin_store.dart';
import '../domain/doctor_report.dart';
import '../services/doctor_report_export.dart';
import '../services/doctor_report_pdf.dart';

/// What the user sees before anything is made or shared.
const doctorReportPrivacyNote =
    'This makes a PDF on your phone from your own logs. Nothing is uploaded '
    'and nobody is sent anything. The file is only saved or shared when you '
    'tap Save or Share, and then it goes where you choose. It lists '
    'substances, amounts, withdrawal symptoms and cravings, so think about '
    'who you hand it to. Personal notes are left out unless you switch them '
    'on.';

enum _RangePreset {
  days30('Last 30 days', 30),
  days90('Last 90 days', 90),
  days180('Last 6 months', 180),
  all('Everything', 0),
  custom('Pick dates', -1);

  const _RangePreset(this.label, this.days);
  final String label;
  final int days;
}

class DoctorReportScreen extends ConsumerStatefulWidget {
  const DoctorReportScreen({
    this.exporter,
    this.loadFonts,
    this.now,
    super.key,
  });

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const DoctorReportScreen()));

  /// Injected by tests so no platform screen opens.
  final DoctorReportExporter? exporter;
  final Future<DoctorReportFonts> Function()? loadFonts;
  final DateTime? now;

  @override
  ConsumerState<DoctorReportScreen> createState() => _DoctorReportScreenState();
}

class _DoctorReportScreenState extends ConsumerState<DoctorReportScreen> {
  _RangePreset _preset = _RangePreset.days30;
  DateTimeRange? _custom;
  bool _includeNotes = false;
  bool _busy = false;
  late final TextEditingController _medicines;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _medicines = TextEditingController(
      text: ref.read(recoveryProvider).reportMedicines,
    );
  }

  @override
  void dispose() {
    _medicines.dispose();
    super.dispose();
  }

  DateTime? _firstEvent() {
    final events = ref.read(recoveryProvider).events;
    if (events.isEmpty) return null;
    return events
        .map((e) => e.timestamp)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DoctorReportRange get _range {
    final now = _now;
    switch (_preset) {
      case _RangePreset.custom:
        final c = _custom;
        if (c != null) return DoctorReportRange(c.start, c.end);
        return DoctorReportRange.lastDays(30, now);
      case _RangePreset.all:
        return DoctorReportRange(_firstEvent()?.toLocal() ?? now, now);
      default:
        return DoctorReportRange.lastDays(_preset.days, now);
    }
  }

  Future<void> _pickDates() async {
    final now = _now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _custom,
    );
    if (picked != null && mounted) {
      setState(() {
        _custom = picked;
        _preset = _RangePreset.custom;
      });
    }
  }

  Future<Uint8List?> _build() async {
    final controller = ref.read(recoveryProvider);
    await controller.updateReportMedicines(_medicines.text);
    final checkIns = await ref.read(symptomCheckInStoreProvider).load();
    final data = buildDoctorReport(
      events: controller.events,
      checkIns: checkIns,
      range: _range,
      now: _now,
      companion: controller.companion,
      medicines: controller.reportMedicines,
    );
    final fonts = await (widget.loadFonts ?? DoctorReportFonts.load)();
    return buildDoctorReportPdf(
      data,
      fonts: fonts,
      options: DoctorReportOptions(includeNotes: _includeNotes),
    );
  }

  Future<void> _run(Future<void> Function(Uint8List bytes) deliver) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _build();
      if (bytes == null) return;
      await deliver(bytes);
    } catch (_) {
      if (mounted) {
        AppNotice.show(
          context,
          'Could not make or save the PDF. Nothing was sent anywhere. Your data is intact.',
          type: AppNoticeType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run((bytes) async {
    final exporter = widget.exporter ?? DoctorReportExporter();
    final saved = await exporter.save(bytes, doctorReportFileName(_range));
    if (!mounted) return;
    AppNotice.show(
      context,
      saved ? 'Saved where you chose.' : 'Cancelled. Nothing was saved.',
      type: saved ? AppNoticeType.success : AppNoticeType.info,
    );
  });

  Future<void> _share() => _run((bytes) async {
    final exporter = widget.exporter ?? DoctorReportExporter();
    await exporter.share(bytes, doctorReportFileName(_range));
  });

  @override
  Widget build(BuildContext context) {
    final range = _range;
    String d(DateTime t) => DateFormat('d MMM yyyy').format(t);
    return Scaffold(
      appBar: AppBar(title: const Text('Doctor summary (PDF)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'A plain summary you can hand to a doctor: your use timeline in ml, '
            'withdrawal check-ins, cravings, medicines you note, and clean '
            'stretches. It works with no internet.',
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          Text('PERIOD', style: eyebrowStyle.copyWith(color: cyan)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _RangePreset.values)
                ChoiceChip(
                  key: ValueKey('report-range-${p.name}'),
                  label: Text(p.label),
                  selected: _preset == p,
                  onSelected: (_) {
                    if (p == _RangePreset.custom) {
                      _pickDates();
                    } else {
                      setState(() => _preset = p);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${d(range.start)} to ${d(range.end)}  (${range.dayCount} days)',
            key: const ValueKey('report-range-label'),
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 16),
          Text(
            'MEDICINES FOR YOUR DOCTOR TO SEE',
            style: eyebrowStyle.copyWith(color: cyan),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('report-medicines'),
            controller: _medicines,
            maxLines: 3,
            maxLength: 600,
            decoration: const InputDecoration(
              hintText:
                  'Optional. e.g. sertraline 50 mg morning, ibuprofen as needed',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('report-include-notes'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Include my personal notes'),
            subtitle: const Text(
              'Off keeps free-text notes on use entries out of the PDF.',
            ),
            value: _includeNotes,
            onChanged: (v) => setState(() => _includeNotes = v),
          ),
          const SizedBox(height: 8),
          GlassCard(
            key: const ValueKey('report-privacy-note'),
            accent: purple,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, size: 18, color: purple),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    doctorReportPrivacyNote,
                    style: TextStyle(fontSize: 11.5, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'If you are worried about your safety, tell your doctor or your SOS '
            'contact. This report has no helpline numbers.',
            style: const TextStyle(fontSize: 11, color: muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('report-save'),
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            label: Text(_busy ? 'Making PDF...' : 'Save PDF'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('report-share'),
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.ios_share),
            label: const Text('Share PDF'),
          ),
        ],
      ),
    );
  }
}
