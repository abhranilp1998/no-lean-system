import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/events_csv.dart';
import 'package:no_lean/features/recovery/domain/recovery_event.dart';

List<List<String>> parseCsv(String csv) {
  // Minimal RFC 4180 parser for round-trip checks.
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  final body = csv.startsWith('\uFEFF') ? csv.substring(1) : csv;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < body.length && body[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\r' && i + 1 < body.length && body[i + 1] == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
      i++;
    } else {
      cell.write(c);
    }
  }
  return rows;
}

void main() {
  final relapse = RecoveryEvent.create(
    type: RecoveryEventType.relapse,
    timestamp: DateTime(2026, 10, 7, 22, 15),
    metadata: {
      'relapseType': 'partial',
      'note': 'Friend said "just one", I went, then\nregretted it',
      'attemptedSos': true,
      'postSos': false,
      'streakLost': 6,
      'quantity': '=HYPERLINK("x")',
      'contextTags': ['Friends', 'Party, late'],
    },
  );
  final craving = RecoveryEvent.create(
    type: RecoveryEventType.craving,
    timestamp: DateTime(2026, 10, 7, 18),
    metadata: {'intensity': 8, 'trigger': 'Stress', 'note': ''},
  );
  final pledge = RecoveryEvent.create(
    type: RecoveryEventType.pledge,
    timestamp: DateTime(2026, 10, 8, 9),
  );
  final milestone = RecoveryEvent.create(
    type: RecoveryEventType.milestone,
    timestamp: DateTime(2026, 10, 9, 0),
    metadata: {'days': 7, 'label': 'ONE WEEK'},
  );

  test('header, BOM, CRLF and oldest-first rows', () {
    final csv = buildEventsCsv([pledge, milestone, relapse, craving]);
    expect(csv.startsWith('\uFEFFid,type,timestamp,'), isTrue);
    expect(csv.endsWith('\r\n'), isTrue);
    final rows = parseCsv(csv);
    expect(rows.first, eventsCsvColumns);
    expect(rows.skip(1).map((r) => r[1]), [
      'craving',
      'relapse',
      'pledge',
      'milestone',
    ]);
    expect(rows.every((r) => r.length == eventsCsvColumns.length), isTrue);
  });

  test('relapse fields round-trip through quoting', () {
    final rows = parseCsv(buildEventsCsv([relapse]));
    final row = Map.fromIterables(eventsCsvColumns, rows[1]);
    expect(row['relapse_type'], 'partial');
    expect(row['attempted_sos'], 'true');
    expect(row['post_sos'], 'false');
    expect(row['streak_lost'], '6');
    expect(row['note'], 'Friend said "just one", I went, then\nregretted it');
    expect(row['context_tags'], 'Friends; Party, late');
    expect(row['date'], '2026-10-07');
  });

  test('formula-looking text is neutralised', () {
    final rows = parseCsv(buildEventsCsv([relapse]));
    final row = Map.fromIterables(eventsCsvColumns, rows[1]);
    expect(row['quantity'], "'=HYPERLINK(\"x\")");
    expect(csvText('-5 cans'), "'-5 cans");
    expect(csvText('@home'), "'@home");
    expect(csvText('fine'), 'fine');
  });

  test('timestamps are ISO 8601 with the UTC offset', () {
    final local = DateTime(2026, 10, 7, 18);
    final iso = isoWithOffset(local);
    expect(iso, startsWith('2026-10-07T18:00:00.000'));
    expect(iso, matches(RegExp(r'[+-]\d{2}:\d{2}$')));
    expect(DateTime.parse(iso).isAtSameMomentAs(local), isTrue);
    expect(isoWithOffset(DateTime.utc(2026, 1, 1)), '2026-01-01T00:00:00.000Z');
  });

  test('unmapped metadata is kept in details as JSON', () {
    final rows = parseCsv(buildEventsCsv([milestone]));
    final row = Map.fromIterables(eventsCsvColumns, rows[1]);
    expect(row['milestone_days'], '7');
    expect(row['details'], '{"label":"ONE WEEK"}');
  });

  test('escaping rules', () {
    expect(csvEscape('plain'), 'plain');
    expect(csvEscape('a,b'), '"a,b"');
    expect(csvEscape('say "hi"'), '"say ""hi"""');
    expect(csvEscape(' padded'), '" padded"');
    expect(csvEscape('line\r\nbreak'), '"line\r\nbreak"');
  });

  test('every event type exports a row', () {
    Map<String, dynamic> metaFor(RecoveryEventType type) => switch (type) {
      RecoveryEventType.daySummary => {'date': '2026-10-01', 'clean': true},
      RecoveryEventType.craving => {'intensity': 5, 'trigger': 'Boredom'},
      RecoveryEventType.codeSession => {
        'taskId': 'word-count',
        'plannedSeconds': 600,
        'durationSeconds': 600,
        'completed': true,
      },
      _ => {},
    };
    final events = [
      for (final type in RecoveryEventType.values)
        RecoveryEvent.create(
          type: type,
          timestamp: DateTime(2026, 10, 1, 12),
          metadata: metaFor(type),
        ),
    ];
    final rows = parseCsv(buildEventsCsv(events));
    expect(
      rows.skip(1).map((r) => r[1]).toSet(),
      RecoveryEventType.values.map((t) => t.name).toSet(),
    );
    final summary = rows.firstWhere((r) => r[1] == 'daySummary');
    expect(summary[3], '2026-10-01');
    expect(summary.last, '{"clean":true}');
  });
}
