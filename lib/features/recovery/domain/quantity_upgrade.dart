import 'dose_units.dart';
import 'recovery_event.dart';

/// Adds structured dose fields to relapse events whose free-text quantity
/// parses exactly (e.g. "250ml", "2.5 bottles"). The original text is kept;
/// events that already carry a unit, or whose text does not parse, are
/// returned unchanged. Marked `amountSource: 'parsed'` so the UI and exports
/// can tell a converted value from one the user entered.
List<RecoveryEvent> upgradeQuantityText(
  List<RecoveryEvent> events, {
  required double bottleMl,
}) => [
  for (final event in events) upgradeEventQuantity(event, bottleMl: bottleMl),
];

RecoveryEvent upgradeEventQuantity(
  RecoveryEvent event, {
  required double bottleMl,
}) {
  if (event.type != RecoveryEventType.relapse) return event;
  final metadata = event.metadata;
  final quantity = metadata['quantity'];
  if (quantity is! String ||
      metadata.containsKey('unit') ||
      metadata.containsKey('amount')) {
    return event;
  }
  final dose = parseQuantityText(quantity, bottleMl: bottleMl);
  if (dose == null) return event;
  return event.copyWith(
    metadata: {...metadata, ...dose.toMetadata(), 'amountSource': 'parsed'},
  );
}
