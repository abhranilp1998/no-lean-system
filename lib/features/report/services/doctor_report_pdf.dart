import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../recovery/domain/dose_units.dart';
import '../domain/doctor_report.dart';

/// Options the user picks on the report screen.
class DoctorReportOptions {
  const DoctorReportOptions({this.includeNotes = false});

  /// Free-text notes on use entries are private by default.
  final bool includeNotes;
}

/// Fonts are the two bundled with the app, so nothing is fetched at any
/// point. [display] is bold and condensed; [body] is the monospace face.
class DoctorReportFonts {
  const DoctorReportFonts({required this.body, required this.display});

  final ByteData body;
  final ByteData display;

  static Future<DoctorReportFonts> load() async => DoctorReportFonts(
    body: await rootBundle.load('assets/fonts/NoLeanMono.ttf'),
    display: await rootBundle.load('assets/fonts/NoLeanDisplay.ttf'),
  );
}

String doctorReportFileName(DoctorReportRange range) {
  String d(DateTime t) => DateFormat('yyyy-MM-dd').format(t);
  return 'no-lean-doctor-summary-${d(range.start)}-to-${d(range.end)}.pdf';
}

const doctorReportAbout =
    'Self-reported by the person named below using the NO LEAN app on their '
    'own phone. It is a personal log, not a medical record or a diagnosis, '
    'and nobody has verified it. Amounts are as the person entered them; '
    'volumes in ml were converted at the time of logging using the bottle '
    'size they had set then. Tablet and drink counts are not converted.';

const doctorReportSafetyNote =
    'If you are worried about this person\'s safety, please use your '
    'clinic\'s own process and their SOS contact. This report lists no '
    'helplines.';

/// Builds the PDF fully in memory. No network, no files: the caller decides
/// whether to save or share the bytes.
Future<Uint8List> buildDoctorReportPdf(
  DoctorReportData data, {
  required DoctorReportFonts fonts,
  DoctorReportOptions options = const DoctorReportOptions(),
}) async {
  final body = pw.Font.ttf(fonts.body);
  final bold = pw.Font.ttf(fonts.display);
  final theme = pw.ThemeData.withFont(
    base: body,
    bold: bold,
    italic: body,
    boldItalic: bold,
    fontFallback: [body, bold],
  );
  final doc = pw.Document(
    title: 'NO LEAN doctor summary',
    author: 'NO LEAN (made on the phone)',
    subject: 'Self-reported use and withdrawal log',
    creator: 'NO LEAN',
    theme: theme,
  );

  String date(DateTime t) => DateFormat('d MMM yyyy').format(t);
  String dateTime(DateTime t) => DateFormat('d MMM yyyy, h:mm a').format(t);
  const ink = PdfColors.grey900;
  const soft = PdfColors.grey700;
  const rule = PdfColors.grey400;
  const alert = PdfColor.fromInt(0xFFB3261E);

  pw.Widget h(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 5),
    child: pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(font: bold, fontSize: 12, color: ink),
    ),
  );
  pw.Widget p(String text, {double size = 9, PdfColor color = ink}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: size, color: color),
        ),
      );
  pw.Widget table(
    List<String> headers,
    List<List<String>> rows, {
    Map<int, pw.TableColumnWidth>? widths,
    Set<int> rightAlign = const {},
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerStyle: pw.TextStyle(
      font: bold,
      fontSize: 8.5,
      color: PdfColors.white,
    ),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey800),
    cellStyle: const pw.TextStyle(fontSize: 8, color: ink),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: rule, width: .4),
      bottom: pw.BorderSide(color: rule, width: .4),
    ),
    headerAlignment: pw.Alignment.centerLeft,
    cellAlignments: {
      for (var i = 0; i < headers.length; i++)
        i: rightAlign.contains(i)
            ? pw.Alignment.topRight
            : pw.Alignment.topLeft,
    },
    columnWidths: widths,
  );

  final cravings = data.cravings;
  final summary = <(String, String)>[
    ('Period', '${date(data.range.start)} to ${date(data.range.end)}'),
    ('Days covered', '${data.range.dayCount}'),
    ('Use entries logged', '${data.entriesTotal}'),
    ('Entries taken together with another depressant', '${data.mixedEntries}'),
    ('Withdrawal check-ins', '${data.checkIns.length}'),
    ('Cravings logged', '${cravings.count}'),
    (
      'Longest clean stretch in the period',
      data.longestStreakDays == 0
          ? 'none full day'
          : '${data.longestStreakDays} days',
    ),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 46),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: rule, width: .4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Made on the phone by NO LEAN on ${date(data.generatedAt)}. '
              'Self-reported.',
              style: const pw.TextStyle(fontSize: 7, color: soft),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: soft),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Text(
          'DOCTOR SUMMARY',
          style: pw.TextStyle(font: bold, fontSize: 24, color: ink),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Use, withdrawal and craving log  |  ${date(data.range.start)} to '
          '${date(data.range.end)}',
          style: const pw.TextStyle(fontSize: 10, color: soft),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: rule, width: .6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              p(doctorReportAbout, size: 8.5),
              p(doctorReportSafetyNote, size: 8.5),
              pw.SizedBox(height: 4),
              p(
                'Name: ______________________    Doctor: ______________________',
                size: 9,
              ),
              p(
                'SOS contact (name, number): ________________________________',
                size: 9,
              ),
            ],
          ),
        ),
        h('Summary'),
        table(
          const ['Item', 'Value'],
          [
            for (final s in summary) [s.$1, s.$2],
          ],
          widths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(2),
          },
        ),
        if (data.hasRedFlags) ...[
          h('Please note'),
          pw.Text(
            'At least one check-in below ticked a serious symptom. These are '
            'marked "RED FLAG".',
            style: pw.TextStyle(font: bold, fontSize: 9, color: alert),
          ),
        ],
        h('Use by substance'),
        if (data.totals.isEmpty)
          p('No use was logged in this period.')
        else ...[
          table(
            const [
              'Substance',
              'Entries',
              'Use days',
              'Total ml',
              'Largest ml',
              'Avg ml / use day',
            ],
            [
              for (final t in data.totals)
                [
                  t.substance.label,
                  '${t.entries}',
                  '${t.useDays}',
                  t.volumeEntries == 0 ? '-' : formatMl(t.totalMl),
                  t.volumeEntries == 0 ? '-' : formatMl(t.maxMl),
                  t.avgMlPerUseDay == null ? '-' : formatMl(t.avgMlPerUseDay!),
                ],
            ],
            widths: {
              0: const pw.FlexColumnWidth(3),
              for (var i = 1; i < 6; i++) i: const pw.FlexColumnWidth(1.4),
            },
            rightAlign: {1, 2, 3, 4, 5},
          ),
          pw.SizedBox(height: 3),
          p(
            'ml figures cover entries with a volume only; tablets and drinks '
            'are counted in Entries but not in ml. Benzodiazepine-only '
            'entries do not reset the codeine / lean clean timer.',
            size: 7.5,
            color: soft,
          ),
          p(
            data.mixedEntries == 0
                ? 'Mixing: none logged. No entry combined codeine with '
                      'alcohol or a benzodiazepine.'
                : 'Mixing: ${data.mixedEntries} '
                      '${data.mixedEntries == 1 ? 'entry was' : 'entries were'}'
                      ' taken together with another depressant (codeine with '
                      'alcohol or a benzodiazepine, within 6 hours). '
                      'Flagged "MIXED" in the timeline.',
            color: data.mixedEntries == 0 ? ink : alert,
          ),
        ],
        h('Use timeline'),
        if (data.entries.isEmpty)
          p('No use was logged in this period.')
        else ...[
          if (data.truncated)
            p(
              'Showing the most recent ${data.entries.length} of '
              '${data.entriesTotal} entries. Choose a shorter period to see '
              'the rest.',
              size: 8,
              color: alert,
            ),
          table(
            [
              'When',
              'Substance',
              'Amount',
              'Mixed',
              if (options.includeNotes) 'Note',
            ],
            [
              for (final e in data.entries)
                [
                  dateTime(e.at),
                  e.substance.label,
                  e.amountText.isEmpty ? '-' : e.amountText,
                  e.mixed ? 'MIXED' : '',
                  if (options.includeNotes) e.note,
                ],
            ],
            widths: {
              0: const pw.FlexColumnWidth(2.4),
              1: const pw.FlexColumnWidth(2.4),
              2: const pw.FlexColumnWidth(2.6),
              3: const pw.FlexColumnWidth(1),
              if (options.includeNotes) 4: const pw.FlexColumnWidth(3),
            },
          ),
          if (!options.includeNotes)
            p(
              'Personal notes were left out of this report.',
              size: 7.5,
              color: soft,
            ),
        ],
        h('Withdrawal symptoms and check-ins'),
        if (data.checkIns.isEmpty)
          p('No check-ins were logged in this period.')
        else ...[
          table(
            const ['When', 'Symptoms (1 mild to 3 severe)', 'Red flags'],
            [
              for (final c in data.checkIns)
                [
                  dateTime(c.at),
                  c.symptoms.isEmpty
                      ? 'None ticked'
                      : c.symptoms
                            .map((s) => '${s.label} ${s.severity}')
                            .join(', '),
                  c.redFlags.isEmpty
                      ? ''
                      : 'RED FLAG: ${c.redFlags.join(', ')}',
                ],
            ],
            widths: {
              0: const pw.FlexColumnWidth(2.2),
              1: const pw.FlexColumnWidth(4.4),
              2: const pw.FlexColumnWidth(3),
            },
          ),
        ],
        h('Cravings'),
        if (cravings.count == 0)
          p('No cravings were logged in this period.')
        else ...[
          p(
            '${cravings.count} logged. Average intensity '
            '${cravings.averageIntensity.toStringAsFixed(1)} of 10, peak '
            '${cravings.peakIntensity} of 10.',
          ),
          if (cravings.topBands.isNotEmpty)
            p(
              'Most often: ${cravings.topBands.map((b) => '${b.label} (${b.count})').join(', ')}.',
            ),
          if (cravings.topTriggers.isNotEmpty)
            p(
              'Triggers named: ${cravings.topTriggers.map((t) => '${t.label} (${t.count})').join(', ')}.',
            ),
          if (cravings.recheckOutcomes.isNotEmpty)
            p(
              'After a 15-minute recheck: ${cravings.recheckOutcomes.entries.map((e) => '${e.key} (${e.value})').join(', ')}.',
            ),
          if (cravings.sosCompleted + cravings.codeCompleted > 0)
            p(
              'Breathing (SOS) or Code Instead sessions finished: '
              '${cravings.sosCompleted + cravings.codeCompleted}.',
            ),
        ],
        h('Medicines and substances noted'),
        if (data.medicines.isEmpty && data.declaredSubstances.isEmpty)
          p('Nothing noted. The app does not keep a medicine list.')
        else ...[
          if (data.medicines.isNotEmpty)
            p('Medicines the person wanted you to see: ${data.medicines}'),
          if (data.declaredSubstances.isNotEmpty)
            p(
              'Substances they told the app they use: '
              '${data.declaredSubstances.join(', ')}.',
            ),
        ],
        h('Clean stretches'),
        if (data.streaks.isEmpty)
          p('No clean stretch of a full day in this period.')
        else ...[
          table(
            const ['From', 'To', 'Days'],
            [
              for (final s in data.streaks)
                [
                  '${date(s.from)}${s.startedBeforeRange ? ' (or earlier)' : ''}',
                  s.ongoing ? 'ongoing' : date(s.to),
                  '${s.days}',
                ],
            ],
            widths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1),
            },
            rightAlign: {2},
          ),
          pw.SizedBox(height: 3),
          p(
            'A stretch ends at the next logged use other than a benzodiazepine. '
            'Benzodiazepine-only entries do not break it.',
            size: 7.5,
            color: soft,
          ),
        ],
      ],
    ),
  );
  return doc.save();
}
