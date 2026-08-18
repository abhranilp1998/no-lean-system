import 'package:uuid/uuid.dart';

enum RecoveryEventType {
  pledge,        // Daily "mark today clean" / "I WILL NOT BUY LEAN TODAY"
  craving,       // Craving logged — metadata: {intensity, trigger, note}
  sosStart,      // SOS breathing session started
  sosComplete,   // SOS breathing session completed — metadata: {durationSeconds, debrief}
  relapse,       // Relapse recorded — metadata: {postSos, streakLost}
  cleanCheckIn,  // "I'm safe" from notification action
  milestone,     // Auto-generated when streak hits a milestone — metadata: {days}
  settingsChange,// Settings mutation — metadata: {field, from, to}
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
      metadata: metadata ?? const {},
    );
  }

  /// Copies this event, allowing mutation of metadata only.
  RecoveryEvent copyWith({
    Map<String, dynamic>? metadata,
  }) {
    return RecoveryEvent._(
      id: id,
      type: type,
      timestamp: timestamp,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Deserializes a RecoveryEvent from JSON.
  factory RecoveryEvent.fromJson(Map<String, dynamic> json) {
    return RecoveryEvent._(
      id: json['id'] as String,
      type: RecoveryEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RecoveryEventType.pledge,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
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
