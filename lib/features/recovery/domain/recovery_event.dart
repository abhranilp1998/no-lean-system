import 'package:uuid/uuid.dart';

enum RecoveryEventType {
  daySummary, // Legacy date-only fact; occurrence count/time were not recorded.
  recoveryStart, // Counter baseline. This is not evidence of a relapse.
  pledge, // Daily "mark today clean" / "I WILL NOT BUY LEAN TODAY"
  craving, // Craving logged — metadata: {intensity, trigger, note}
  sosStart, // SOS breathing session started
  sosComplete, // SOS breathing session completed — metadata: {durationSeconds, debrief}
  relapse, // Relapse recorded — metadata: {postSos, streakLost}
  cleanCheckIn, // "I'm safe" from notification action
  milestone, // Auto-generated when streak hits a milestone — metadata: {days}
  settingsChange, // Settings mutation — metadata: {field, from, to}
}

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
        if (postSos != null && postSos is! bool) {
          throw const FormatException('postSos must be true or false.');
        }
        if (streakLost != null && streakLost is! num) {
          throw const FormatException('streakLost must be a number.');
        }
        if (debrief != null && debrief is! String) {
          throw const FormatException('Relapse debrief must be text.');
        }
        if (streakLost is num) result['streakLost'] = streakLost.round();
        if (debrief is String) result['debrief'] = debrief.trim();
      case RecoveryEventType.milestone:
        final days = result['days'];
        if (days != null && (days is! num || days < 0)) {
          throw const FormatException('Milestone days must be non-negative.');
        }
        if (days is num) result['days'] = days.round();
      case RecoveryEventType.recoveryStart:
      case RecoveryEventType.pledge:
      case RecoveryEventType.sosStart:
      case RecoveryEventType.cleanCheckIn:
      case RecoveryEventType.settingsChange:
        break;
    }
    return result;
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
