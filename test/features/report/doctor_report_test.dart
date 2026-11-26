import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/companion/domain/companion_state.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';
import 'package:no_lean/features/recovery/services/android_document_export.dart';
import 'package:no_lean/features/report/domain/doctor_report.dart';
import 'package:no_lean/features/report/services/doctor_report_export.dart';
import 'package:no_lean/features/report/services/doctor_report_pdf.dart';
import 'package:no_lean/features/withdrawal/domain/withdrawal_guide.dart';

import '../../support/recap_events.dart';

DoctorReportFonts testFonts() => DoctorReportFonts(
  body: ByteData.sublistView(
    File('assets/fonts/NoLeanMono.ttf').readAsBytesSync(),
  ),
  display: ByteData.sublistView(
    File('assets/fonts/NoLeanDisplay.ttf').readAsBytesSync(),
  ),
);

/// A varied month used by the data tests and the rendered sample page.
({List<RecoveryEvent> events, List<SymptomCheckIn> checkIns}) sampleMonth() {
  final events = <RecoveryEvent>[
    startAt(DateTime(2026, 8, 1)),
    // Earlier slip, before the period.
    relapseAt(DateTime(2026, 10, 3, 22)),
    // Within the period.
    relapseAt(
      DateTime(2026, 11, 2, 21, 30),
      extra: {
        'amount': 2.5,
        'unit': 'bottle',
        'bottleMl': 100,
        'amountMl': 250,
        'note': 'Rough night after an argument',
      },
    ),
    relapseAt(
      DateTime(2026, 11, 2, 22),
      type: 'alcohol',
      extra: {
        'amount': 3,
        'unit': 'drink',
        'batchId': 'b1',
        'recordedAt': '2026-11-02T22:05:00',
      },
    ),
    relapseAt(
      DateTime(2026, 11, 2, 21, 30),
      type: 'fullLean',
      extra: {
        'amount': 250,
        'unit': 'ml',
        'amountMl': 250,
        'batchId': 'b1',
        'recordedAt': '2026-11-02T22:05:00',
      },
    ),
    relapseAt(
      DateTime(2026, 11, 9, 23),
      type: 'benzo',
      extra: {'amount': 2, 'unit': 'tablet'},
    ),
    relapseAt(
      DateTime(2026, 11, 15, 20),
      type: 'partial',
      extra: {'amount': 40, 'unit': 'ml', 'amountMl': 40},
    ),
    for (var d = 3; d < 20; d += 4) cravingAt(DateTime(2026, 11, d, 21, 15)),
    cravingAt(DateTime(2026, 11, 20, 14), intensity: 9, trigger: 'Stress'),
    recheckAt(DateTime(2026, 11, 3, 21, 40), 'eased'),
    sosDoneAt(DateTime(2026, 11, 7, 21)),
  ];
  final checkIns = [
    SymptomCheckIn(
      at: DateTime(2026, 11, 3, 10),
      severities: {Symptom.anxiety: 2, Symptom.sleep: 3, Symptom.aches: 1},
    ),
    SymptomCheckIn(
      at: DateTime(2026, 11, 16, 9),
      severities: {Symptom.anxiety: 1, Symptom.dizzyFaint: 2},
    ),
    SymptomCheckIn(at: DateTime(2026, 9, 1), severities: {Symptom.anxiety: 3}),
  ];
  return (events: events, checkIns: checkIns);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 27, 12);
  final range = DoctorReportRange(
    DateTime(2026, 11, 1),
    DateTime(2026, 11, 27),
  );

  DoctorReportData build({
    DoctorReportRange? r,
    String medicines = '',
    CompanionState? companion,
  }) {
    final m = sampleMonth();
    return buildDoctorReport(
      events: m.events,
      checkIns: m.checkIns,
      range: r ?? range,
      now: now,
      medicines: medicines,
      companion: companion,
    );
  }

  group('data', () {
    test('only the chosen range is included, oldest first', () {
      final data = build();
      expect(data.entriesTotal, 5);
      expect(data.entries.first.at, DateTime(2026, 11, 2, 21, 30));
      expect(data.entries.every((e) => range.contains(e.at)), isTrue);
      expect(data.checkIns.length, 2); // the September one is out of range
    });

    test(
      'amounts keep ml at the time of logging and substances stay apart',
      () {
        final data = build();
        final codeine = data.totals.firstWhere(
          (t) => t.substance == ReportSubstance.codeine,
        );
        expect(codeine.entries, 3);
        expect(codeine.totalMl, 540); // 250 + 250 + 40
        expect(codeine.maxMl, 250);
        expect(codeine.useDays, 2); // two on 2 Nov, one on 15 Nov
        final benzo = data.totals.firstWhere(
          (t) => t.substance == ReportSubstance.benzo,
        );
        expect(benzo.entries, 1);
        expect(benzo.totalMl, 0);
        expect(benzo.avgMlPerUseDay, isNull);
        final bottle = data.entries.firstWhere(
          (e) => e.amountText.contains('bottle'),
        );
        expect(bottle.amountText, '2.5 bottles · 250 ml');
        expect(bottle.ml, 250);
      },
    );

    test('mixing is flagged for one sitting of codeine with alcohol', () {
      final data = build();
      final mixed = data.entries.where((e) => e.mixed).toList();
      expect(mixed.length, 2);
      expect(mixed.map((e) => e.substance).toSet(), {
        ReportSubstance.codeine,
        ReportSubstance.alcohol,
      });
      expect(data.mixedEntries, 2);
    });

    test('benzo-only use is listed but does not break a clean stretch', () {
      final data = build();
      // Stretches in range: 1-2 Nov (start of range to the 2nd, <1 day
      // before 21:30? 1 Nov 00:00 -> 2 Nov 21:30 = 1 day), 2 Nov to 15 Nov,
      // and 15 Nov to now.
      expect(data.streaks.length, 3);
      expect(data.streaks.first.startedBeforeRange, isTrue);
      expect(data.streaks.last.ongoing, isTrue);
      expect(data.streaks[1].days, 12);
      // The benzo entry on 9 Nov sits inside the 12-day stretch.
      expect(data.streaks.where((s) => s.days >= 12).length, 1);
      expect(data.longestStreakDays, greaterThanOrEqualTo(12));
    });

    test('check-ins separate ordinary symptoms from red flags', () {
      final data = build();
      expect(data.hasRedFlags, isTrue);
      final first = data.checkIns.first;
      expect(first.symptoms.length, 3);
      expect(first.redFlags, isEmpty);
      expect(data.checkIns.last.redFlags, ['Dizzy / fainting']);
    });

    test('cravings summarise count, peak, bands, triggers and rechecks', () {
      final c = build().cravings;
      expect(c.count, 6);
      expect(c.peakIntensity, 9);
      expect(c.topBands.first.label, '9 PM–12 AM');
      expect(c.topTriggers.first.label, 'Evenings');
      expect(c.recheckOutcomes, {'eased': 1});
      expect(c.sosCompleted, 1);
    });

    test(
      'medicines and declared substances are carried, nothing is invented',
      () {
        final data = build(
          medicines: ' sertraline 50 mg ',
          companion: const CompanionState(substances: {Substance.codeine}),
        );
        expect(data.medicines, 'sertraline 50 mg');
        expect(data.declaredSubstances, ['Codeine / lean']);
        expect(build().medicines, isEmpty);
        expect(build().declaredSubstances, isEmpty);
      },
    );

    test('an empty period still builds', () {
      final data = build(
        r: DoctorReportRange(DateTime(2025, 1, 1), DateTime(2025, 1, 31)),
      );
      expect(data.entries, isEmpty);
      expect(data.totals, isEmpty);
      expect(data.cravings.count, 0);
      expect(data.checkIns, isEmpty);
    });

    test('very long ranges keep the most recent rows and say so', () {
      final many = [
        startAt(DateTime(2024, 1, 1)),
        for (var i = 0; i < doctorReportMaxRows + 50; i++)
          relapseAt(
            DateTime(2025, 1, 1).add(Duration(hours: i)),
            type: 'alcohol',
          ),
      ];
      final data = buildDoctorReport(
        events: many,
        checkIns: const [],
        range: DoctorReportRange(DateTime(2025, 1, 1), DateTime(2025, 12, 31)),
        now: DateTime(2026, 1, 1),
      );
      expect(data.entries.length, doctorReportMaxRows);
      expect(data.entriesTotal, doctorReportMaxRows + 50);
      expect(data.truncated, isTrue);
      expect(
        data.entries.last.at,
        DateTime(2025, 1, 1).add(Duration(hours: doctorReportMaxRows + 49)),
      );
    });

    test('the range rejects an end before the start', () {
      expect(
        () => DoctorReportRange(DateTime(2026, 11, 5), DateTime(2026, 11, 1)),
        throwsArgumentError,
      );
    });
  });

  group('pdf', () {
    test('builds a valid offline PDF with the expected content', () async {
      final data = build(medicines: 'sertraline 50 mg');
      final bytes = await buildDoctorReportPdf(data, fonts: testFonts());
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));
      final tail = latin1.decode(bytes.sublist(bytes.length - 64));
      expect(tail, contains('%%EOF'));
      // Fonts are embedded and no network fonts are referenced.
      final text = latin1.decode(bytes);
      expect(text, contains('/FontFile2'));
      // No links, so a viewer never offers to open anything online.
      expect(text, isNot(contains('/URI')));
      expect(text, isNot(contains('/Launch')));
    });

    test('writes a sample PDF when asked (for the PR screenshots)', () async {
      final out = Platform.environment['RECAP_SCREENS'];
      if (out == null) return;
      final bytes = await buildDoctorReportPdf(
        build(
          medicines: 'sertraline 50 mg in the morning; ibuprofen when needed',
          companion: const CompanionState(
            substances: {Substance.codeine, Substance.alcohol},
          ),
        ),
        fonts: testFonts(),
        options: const DoctorReportOptions(includeNotes: true),
      );
      Directory(out).createSync(recursive: true);
      File('$out/doctor-summary.pdf').writeAsBytesSync(bytes);
    });

    test(
      'copy points to the doctor and SOS contact and lists no helplines',
      () {
        const all = '$doctorReportAbout $doctorReportSafetyNote';
        expect(all, contains('SOS contact'));
        expect(all, contains('clinic'));
        expect(all, contains('no helplines'));
        expect(RegExp(r'\b1\d{2}\b').hasMatch(all), isFalse);
        expect(all, isNot(contains('112')));
      },
    );

    test('file names carry the dates and a .pdf extension', () {
      expect(
        doctorReportFileName(range),
        'no-lean-doctor-summary-2026-11-01-to-2026-11-27.pdf',
      );
    });

    test('empty reports and notes on/off both build', () async {
      final empty = build(
        r: DoctorReportRange(DateTime(2025, 1, 1), DateTime(2025, 1, 31)),
      );
      final a = await buildDoctorReportPdf(empty, fonts: testFonts());
      final b = await buildDoctorReportPdf(
        build(),
        fonts: testFonts(),
        options: const DoctorReportOptions(includeNotes: true),
      );
      expect(a.length, greaterThan(1000));
      expect(b.length, greaterThan(1000));
    });
  });

  group('export', () {
    const channel = MethodChannel('no_lean/export');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('Android saves the raw bytes with the PDF MIME type', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'save');
        final args = call.arguments as Map;
        expect(args['mimeType'], 'application/pdf');
        expect(args['fileName'], endsWith('.pdf'));
        expect(utf8.decode((args['bytes'] as Uint8List).sublist(0, 4)), '%PDF');
        return true;
      });
      final pdf = Uint8List.fromList(utf8.encode('%PDF-1.7 test'));
      expect(
        await const AndroidDocumentExport().saveBytes(
          pdf,
          fileName: 'x.pdf',
          mimeType: pdfMimeType,
        ),
        isTrue,
      );
    });

    test('nothing is written or shared until a method is called', () async {
      var saved = 0;
      var shared = 0;
      final exporter = DoctorReportExporter(
        saveBytes: (b, n) async {
          saved++;
          return true;
        },
        share: (p) async => throw StateError('should not be called'),
        temporaryDirectory: () async => Directory.systemTemp,
      );
      expect(saved, 0);
      expect(shared, 0);
      expect(await exporter.save(Uint8List(3), 'a.pdf'), isTrue);
      expect(saved, 1);
    });

    test('the Kotlin whitelist accepts PDF', () {
      final kt = File(
        'android/app/src/main/kotlin/com/nolean/no_lean/DocumentExportChannel.kt',
      ).readAsStringSync();
      expect(kt, contains('"application/pdf"'));
    });
  });
}
