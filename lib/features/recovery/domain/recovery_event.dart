import 'package:uuid/uuid.dart';

import 'dose_units.dart';
import 'relapse_log_entry.dart';

enum RecoveryEventType {
  daySummary, // Legacy date-only fact; occurrence count/time were not recorded.
  recoveryStart, // Counter baseline. This is not evidence of a relapse.
  pledge, // Daily "mark today clean" / "I WILL NOT BUY LEAN TODAY"
  craving, // Craving logged — metadata: {intensity, trigger, note, stress?}
  sosStart, // SOS breathing session started
  sosComplete, // SOS breathing session completed — metadata: {durationSeconds, debrief}
  relapse, // Relapse recorded — metadata: {postSos, streakLost, relapseType, note, quantity?, amount?, unit?, amountMl?, bottleMl?, cost?, stress?}
  cleanCheckIn, // "I'm safe" from notification action
  milestone, // Recorded by RecoveryController.syncMilestones when the streak reaches one — metadata: {days, label, source: 'auto'}
  settingsChange, // Settings mutation — metadata: {field, from, to}
  codeSession, // Code Instead block — metadata: {taskId, task, plannedSeconds, durationSeconds, completed, source}
  zoneEntry, // Opt-in danger-zone visit — metadata: {zoneId, zoneName, source}. Never coordinates.
  cravingCheck, // 15-minute recheck of a craving — metadata: {cravingId, intensity 0-10, outcome}
}

/// How a craving changed by the time it was rechecked.
const cravingCheckOutcomes = {'gone', 'eased', 'same', 'stronger'};

/// Derives the recheck outcome from the original and current intensity.
String cravingCheckOutcome(int original, int current) {
  if (current <= 0) return 'gone';
  if (current < original) return 'eased';
  if (current > original) return 'stronger';
  return 'same';
}

/// Location keys that must never be stored on a zone entry.
const _locationKeys = {
  'latitude',
  'longitude',
  'lat',
  'lng',
  'lon',
  'accuracy',
  'accuracyMeters',
  'radiusMeters',
};

/// An immutable append-only event representing state changes in the recovery journey.
class RecoveryEvent {
  final String id;
  final RecoveryEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const RecoveryEvent._({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.metadata,
  });

  /// Factory constructor to create a new RecoveryEvent with an auto-generated UUID
  /// and timestamp defaulting to now.
  factory RecoveryEvent.create({
    required RecoveryEventType type,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
  }) {
    return RecoveryEvent._(
      id: const Uuid().v4(),
      type: type,
      timestamp: timestamp ?? DateTime.now(),
      metadata: Map.unmodifiable(
        validateMetadata(type, Map<String, dynamic>.from(metadata ?? const {})),
      ),
    );
  }

  /// Copies this event, allowing mutation of metadata only.
  RecoveryEvent copyWith({Map<String, dynamic>? metadata}) {
    return RecoveryEvent._(
      id: id,
      type: type,
      timestamp: timestamp,
      metadata: metadata == null
          ? this.metadata
          : Map.unmodifiable(validateMetadata(type, metadata)),
    );
  }

  /// Deserializes a RecoveryEvent from JSON.
  factory RecoveryEvent.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final typeName = json['type'];
    final timestampValue = json['timestamp'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Recovery event ID is missing.');
    }
    if (typeName is! String) {
      throw const FormatException('Recovery event type is missing.');
    }
    final type = RecoveryEventType.values
        .where((value) => value.name == typeName)
        .firstOrNull;
    if (type == null) {
      throw FormatException('Unsupported recovery event type: $typeName');
    }
    if (timestampValue is! String) {
      throw const FormatException('Recovery event timestamp is missing.');
    }
    final timestamp = DateTime.tryParse(timestampValue);
    if (timestamp == null) {
      throw FormatException(
        'Invalid recovery event timestamp: $timestampValue',
      );
    }
    final metadataValue = json['metadata'];
    if (metadataValue != null && metadataValue is! Map) {
      throw const FormatException('Recovery event metadata must be an object.');
    }

    return RecoveryEvent._(
      id: id,
      type: type,
      timestamp: timestamp,
      metadata: Map.unmodifiable(
        validateMetadata(
          type,
          Map<String, dynamic>.from(metadataValue ?? const {}),
        ),
      ),
    );
  }

  /// Validates metadata fields that are consumed by derived-state code.
  /// Unknown keys are retained so newer non-breaking metadata can round-trip.
  static Map<String, dynamic> validateMetadata(
    RecoveryEventType type,
    Map<String, dynamic> metadata,
  ) {
    final result = Map<String, dynamic>.from(metadata);
    switch (type) {
      case RecoveryEventType.daySummary:
        final date = result['date'];
        if (date is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
            DateTime.tryParse(date) == null ||
            DateTime.parse(date).toIso8601String().substring(0, 10) != date ||
            result['clean'] is! bool) {
          throw const FormatException('Invalid legacy day summary.');
        }
      case RecoveryEventType.craving:
        final intensity = result['intensity'];
        if (intensity is! num || intensity < 1 || intensity > 10) {
          throw const FormatException(
            'Craving intensity must be between 1 and 10.',
          );
        }
        final trigger = result['trigger'];
        final note = result['note'];
        if (trigger is! String || trigger.trim().isEmpty) {
          throw const FormatException('Craving trigger is required.');
        }
        if (note != null && note is! String) {
          throw const FormatException('Craving note must be text.');
        }
        result['intensity'] = intensity.round();
        result['trigger'] = trigger.trim();
        result['note'] = (note as String?)?.trim() ?? '';
        _validateStress(result);
      case RecoveryEventType.cravingCheck:
        final cravingId = result['cravingId'];
        final intensity = result['intensity'];
        final outcome = result['outcome'];
        if (cravingId is! String || cravingId.trim().isEmpty) {
          throw const FormatException('Craving check needs a craving ID.');
        }
        if (intensity is! num || intensity < 0 || intensity > 10) {
          throw const FormatException(
            'Craving check intensity must be between 0 and 10.',
          );
        }
        if (outcome is! String || !cravingCheckOutcomes.contains(outcome)) {
          throw const FormatException(
            'Craving check outcome is not supported.',
          );
        }
        result['intensity'] = intensity.round();
      case RecoveryEventType.sosComplete:
        final startId = result['startId'];
        final debrief = result['debrief'];
        if (startId != null && startId is! String) {
          throw const FormatException('SOS start ID must be text.');
        }
        if (debrief != null && debrief is! String) {
          throw const FormatException('SOS debrief must be text.');
        }
        if (debrief is String) result['debrief'] = debrief.trim();
      case RecoveryEventType.relapse:
        final postSos = result['postSos'];
        final streakLost = result['streakLost'];
        final debrief = result['debrief'];
        final relapseType = result['relapseType'];
        final note = result['note'];
        final attemptedSos = result['attemptedSos'];
        final quantity = result['quantity'];
        final contextTags = result['contextTags'];
        if (postSos != null && postSos is! bool) {
          throw const FormatException('postSos must be true or false.');
        }
        if (streakLost != null && streakLost is! num) {
          throw const FormatException('streakLost must be a number.');
        }
        if (debrief != null && debrief is! String) {
          throw const FormatException('Relapse debrief must be text.');
        }
        if (relapseType != null &&
            RelapseTypeLabel.fromName(relapseType) == null) {
          throw const FormatException('Relapse type is not supported.');
        }
        if (note != null && note is! String) {
          throw const FormatException('Relapse note must be text.');
        }
        if (attemptedSos != null && attemptedSos is! bool) {
          throw const FormatException('attemptedSos must be true or false.');
        }
        if (quantity != null && quantity is! String) {
          throw const FormatException('Relapse quantity must be text.');
        }
        if (contextTags != null &&
            (contextTags is! List ||
                contextTags.any((tag) => tag is! String))) {
          throw const FormatException(
            'Relapse context tags must be a list of text values.',
          );
        }
        if (streakLost is num) result['streakLost'] = streakLost.round();
        if (debrief is String) result['debrief'] = debrief.trim();
        if (note is String) result['note'] = note.trim();
        if (quantity is String) {
          final normalized = quantity.trim();
          if (normalized.isEmpty) {
            result.remove('quantity');
          } else {
            result['quantity'] = normalized;
          }
        }
        _validateDose(result);
        _validateStress(result);
        final cost = result['cost'];
        if (cost != null) {
          if (cost is! num ||
              !cost.isFinite ||
              cost < 0 ||
              cost > maxRelapseCost) {
            throw const FormatException('Relapse cost must be 0 or more.');
          }
          result['cost'] = cost.toDouble();
        }
        if (contextTags is List) {
          final normalized = contextTags
              .cast<String>()
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toSet()
              .toList(growable: false);
          if (normalized.isEmpty) {
            result.remove('contextTags');
          } else {
            result['contextTags'] = normalized;
          }
        }
      case RecoveryEventType.milestone:
        final days = result['days'];
        if (days != null && (days is! num || days < 0)) {
          throw const FormatException('Milestone days must be non-negative.');
        }
        if (days is num) result['days'] = days.round();
      case RecoveryEventType.codeSession:
        final taskId = result['taskId'];
        final task = result['task'];
        final planned = result['plannedSeconds'];
        final duration = result['durationSeconds'];
        final completed = result['completed'];
        if (taskId is! String || taskId.trim().isEmpty) {
          throw const FormatException('Code session task ID is required.');
        }
        if (task != null && task is! String) {
          throw const FormatException('Code session task must be text.');
        }
        if (planned is! num || planned <= 0) {
          throw const FormatException(
            'Code session planned length must be positive.',
          );
        }
        if (duration is! num || duration < 0) {
          throw const FormatException(
            'Code session duration must be non-negative.',
          );
        }
        if (completed is! bool) {
          throw const FormatException(
            'Code session completed must be true or false.',
          );
        }
        result['taskId'] = taskId.trim();
        result['plannedSeconds'] = planned.round();
        result['durationSeconds'] = duration.round();
      case RecoveryEventType.zoneEntry:
        final zoneId = result['zoneId'];
        final zoneName = result['zoneName'];
        if (zoneId is! String || zoneId.trim().isEmpty) {
          throw const FormatException('Zone entry needs a zone ID.');
        }
        if (zoneName is! String || zoneName.trim().isEmpty) {
          throw const FormatException('Zone entry needs a zone name.');
        }
        // Privacy invariant: a zone entry is a name and a time, nothing more.
        result.removeWhere((key, _) => _locationKeys.contains(key));
        result['zoneName'] = zoneName.trim();
      case RecoveryEventType.recoveryStart:
      case RecoveryEventType.pledge:
      case RecoveryEventType.sosStart:
      case RecoveryEventType.cleanCheckIn:
      case RecoveryEventType.settingsChange:
        break;
    }
    return result;
  }

  /// Optional 1-5 stress rating shared by cravings and relapses.
  static void _validateStress(Map<String, dynamic> result) {
    final stress = result['stress'];
    if (stress == null) return;
    if (stress is! num || stress < 1 || stress > 5) {
      throw const FormatException('Stress must be between 1 and 5.');
    }
    result['stress'] = stress.round();
  }

  /// Structured dose: amount + unit as a pair, ml derived for volume units
  /// and never for counts. A bottle dose keeps the ml stored at logging
  /// time; it is only computed when an older writer left it out.
  static void _validateDose(Map<String, dynamic> result) {
    final amount = result['amount'];
    final unitName = result['unit'];
    if (amount == null && unitName == null) {
      result
        ..remove('amountMl')
        ..remove('bottleMl');
      return;
    }
    final unit = DoseUnitInfo.fromName(unitName);
    if (unit == null) {
      throw const FormatException('Dose unit is not supported.');
    }
    if (amount is! num || !amount.isFinite || amount <= 0) {
      throw const FormatException('Dose amount must be greater than zero.');
    }
    result['amount'] = amount.toDouble();
    final source = result['amountSource'];
    if (source != null && source is! String) {
      throw const FormatException('Dose source must be text.');
    }
    switch (unit) {
      case DoseUnit.ml:
      case DoseUnit.litre:
        result['amountMl'] = toMl(amount.toDouble(), unit, bottleMl: 0);
        result.remove('bottleMl');
      case DoseUnit.bottle:
        final bottleMl = result['bottleMl'];
        final amountMl = result['amountMl'];
        if (bottleMl != null &&
            (bottleMl is! num || !isValidBottleMl(bottleMl))) {
          throw const FormatException('Bottle size must be 10-2000 ml.');
        }
        if (amountMl is num && amountMl.isFinite && amountMl > 0) {
          result['amountMl'] = amountMl.toDouble();
        } else if (amountMl == null && bottleMl is num) {
          result['amountMl'] = amount * bottleMl;
        } else {
          throw const FormatException('Bottle dose needs its ml value.');
        }
        if (bottleMl is num) result['bottleMl'] = bottleMl.toDouble();
      case DoseUnit.drink:
      case DoseUnit.tablet:
        result
          ..remove('amountMl')
          ..remove('bottleMl');
    }
  }

  /// Serializes this event to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }
}
