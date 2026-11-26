import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/recovery/application/recovery_controller.dart';
import 'package:no_lean/features/recovery/application/recovery_provider.dart';
import 'package:no_lean/features/report/presentation/doctor_report_screen.dart';
import 'package:no_lean/features/report/services/doctor_report_export.dart';
import 'package:no_lean/features/report/services/doctor_report_pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recap_events.dart';
import '../../support/recovery_fakes.dart';
import 'doctor_report_test.dart' show testFonts;

class _RecordingExporter extends DoctorReportExporter {
  _RecordingExporter()
    : super(temporaryDirectory: () async => Directory.systemTemp);

  final saved = <(Uint8List, String)>[];
  final shared = <String>[];
  bool saveResult = true;

  @override
  Future<bool> save(Uint8List bytes, String fileName) async {
    saved.add((bytes, fileName));
    return saveResult;
  }

  @override
  Future<void> share(Uint8List bytes, String fileName) async {
    shared.add(fileName);
  }
}

/// Taps a button, then lets real I/O (fonts, PDF building) finish.
Future<void> tapAndSettle(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 27, 12);

  Future<RecoveryController> controller() async {
    final c = RecoveryController(
      store: MemoryRecoveryStore(
        jsonEncode({
          'stateVersion': 17,
          'lastDose': DateTime(2026, 11, 20, 22).toIso8601String(),
          'events': [
            startAt(DateTime(2026, 9, 1)).toJson(),
            relapseAt(DateTime(2026, 11, 20, 22)).toJson(),
          ],
        }),
      ),
      relapseLock: FakeRelapseLock(),
    );
    await c.load();
    return c;
  }

  Future<void> pump(
    WidgetTester tester,
    RecoveryController c,
    _RecordingExporter exporter,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [recoveryProvider.overrideWith((ref) => c)],
        child: MaterialApp(
          theme: buildNoLeanTheme(),
          home: DoctorReportScreen(
            exporter: exporter,
            loadFonts: () async => testFonts(),
            now: now,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the privacy note and exports nothing until tapped', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final c = await controller();
    final exporter = _RecordingExporter();
    await pump(tester, c, exporter);

    expect(find.byKey(const ValueKey('report-privacy-note')), findsOneWidget);
    expect(find.textContaining('Nothing is uploaded'), findsOneWidget);
    expect(find.textContaining('SOS'), findsOneWidget);
    expect(find.textContaining('112'), findsNothing);
    expect(exporter.saved, isEmpty);
    expect(exporter.shared, isEmpty);
  });

  testWidgets('range presets and a PDF save with the medicines note', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final c = await controller();
    final exporter = _RecordingExporter();
    await pump(tester, c, exporter);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('report-range-label')))
          .data,
      '29 Oct 2026 to 27 Nov 2026  (30 days)',
    );
    await tester.tap(find.byKey(const ValueKey('report-range-days90')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('report-range-label')))
          .data,
      contains('(90 days)'),
    );

    await tester.enterText(
      find.byKey(const ValueKey('report-medicines')),
      'sertraline 50 mg',
    );
    await tapAndSettle(tester, 'report-save');
    expect(exporter.saved, hasLength(1));
    final (bytes, name) = exporter.saved.single;
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(name, endsWith('.pdf'));
    expect(name, contains('2026-11-27'));
    expect(c.reportMedicines, 'sertraline 50 mg');
    expect(exporter.shared, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a cancelled save says so and keeps nothing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = await controller();
    final exporter = _RecordingExporter()..saveResult = false;
    await pump(tester, c, exporter);
    await tapAndSettle(tester, 'report-save');
    expect(find.text('Cancelled. Nothing was saved.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('share only happens on the share button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = await controller();
    final exporter = _RecordingExporter();
    await pump(tester, c, exporter);
    await tapAndSettle(tester, 'report-share');
    expect(exporter.shared, hasLength(1));
    expect(exporter.saved, isEmpty);
  });

  test('the copy never names a government helpline', () {
    expect(doctorReportPrivacyNote, isNot(contains('112')));
    expect(doctorReportPrivacyNote.toLowerCase(), isNot(contains('helpline')));
    expect(doctorReportSafetyNote, contains('SOS contact'));
  });
}
