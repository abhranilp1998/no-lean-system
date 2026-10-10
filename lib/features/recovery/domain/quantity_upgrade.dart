import 'dose_units.dart';
import 'recovery_event.dart';

/// Adds structured dose fields to relapse events whose free-text quantity
/// parses exactly without an unknown conversion (e.g. "250ml", "2 tablets").
/// Legacy bottle notes have no per-entry bottle size, so their original text
/// stays unstructured. Today's bottle setting applies only to new entries.
/// Existing structured doses and unparseable text remain unchanged. Converted
/// values keep the original text and are marked `amountSource: 'parsed'` so
/// the UI and exports can distinguish them from a value the user entered.
List<RecoveryEvent> upgradeQuantityText(List<RecoveryEvent> events) => [
  for (final event in events) upgradeEventQuantity(event),
];

RecoveryEvent upgradeEventQuantity(RecoveryEvent event) {
  if (event.type != RecoveryEventType.relapse) return event;
  final metadata = event.metadata;
  final quantity = metadata['quantity'];
  if (quantity is! String ||
      metadata.containsKey('unit') ||
      metadata.containsKey('amount')) {
    return event;
  }
  final dose = parseQuantityText(quantity, bottleMl: defaultBottleMl);
  if (dose == null || dose.unit == DoseUnit.bottle) return event;
  return event.copyWith(
    metadata: {...metadata, ...dose.toMetadata(), 'amountSource': 'parsed'},
  );
}
