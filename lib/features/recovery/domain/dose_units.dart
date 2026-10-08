/// Units for logged doses and the rules that convert between them.
///
/// Rules (see memory.md):
/// - Maths happens in ml. L and bottles convert with the user's bottle size
///   *at the time of logging*; the entered amount, unit, ml value and bottle
///   size are all stored, so changing the setting never rewrites history.
/// - Tablets and drinks are counts, not volume. They never enter ml totals
///   and are only compared with the same unit.
/// - Amounts must be finite and greater than zero. Display rounds; storage
///   does not.
enum DoseUnit { ml, litre, bottle, drink, tablet }

const defaultBottleMl = 100.0;
const minBottleMl = 10.0;
const maxBottleMl = 2000.0;

/// Common bottle sizes offered in settings (ml).
const bottleSizePresets = <double>[60, 100, 120, 200, 250, 330, 500, 750];

/// Hard input ceilings: anything above is a typo, not a dose.
const maxDoseMl = 20000.0;
const maxDoseCount = 500.0;

extension DoseUnitInfo on DoseUnit {
  bool get isVolume => switch (this) {
    DoseUnit.ml || DoseUnit.litre || DoseUnit.bottle => true,
    DoseUnit.drink || DoseUnit.tablet => false,
  };

  /// Short label for chips and compact displays.
  String get label => switch (this) {
    DoseUnit.ml => 'ml',
    DoseUnit.litre => 'L',
    DoseUnit.bottle => 'bottles',
    DoseUnit.drink => 'drinks',
    DoseUnit.tablet => 'tablets',
  };

  String labelFor(double amount) {
    final one = (amount - 1).abs() < 1e-9;
    return switch (this) {
      DoseUnit.ml => 'ml',
      DoseUnit.litre => 'L',
      DoseUnit.bottle => one ? 'bottle' : 'bottles',
      DoseUnit.drink => one ? 'drink' : 'drinks',
      DoseUnit.tablet => one ? 'tablet' : 'tablets',
    };
  }

  static DoseUnit? fromName(Object? value) => value is String
      ? DoseUnit.values.where((unit) => unit.name == value).firstOrNull
      : null;
}

/// True for a usable bottle size setting.
bool isValidBottleMl(num? value) =>
    value != null &&
    value.isFinite &&
    value >= minBottleMl &&
    value <= maxBottleMl;

/// Converts to ml for volume units; null for counts (tablets, drinks).
double? toMl(double amount, DoseUnit unit, {required double bottleMl}) =>
    switch (unit) {
      DoseUnit.ml => amount,
      DoseUnit.litre => amount * 1000,
      DoseUnit.bottle => amount * bottleMl,
      DoseUnit.drink || DoseUnit.tablet => null,
    };

const _wordAmounts = <String, double>{
  'half': .5,
  'a half': .5,
  'one half': .5,
  '½': .5,
  'quarter': .25,
  'a quarter': .25,
  'one quarter': .25,
  '¼': .25,
  'three quarters': .75,
  'three quarter': .75,
  '¾': .75,
  'a': 1,
  'an': 1,
  'one': 1,
};

final _plainNumber = RegExp(r'^(\d+([.,]\d+)?|[.,]\d+)$');
final _thousandsLike = RegExp(r'^\d{1,3},\d{3}$');
final _fraction = RegExp(r'^(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)$');
final _mixedFraction = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$');
final _andAHalf = RegExp(r'^(\d+)\s*(?:and a half|½)$');

/// Parses a typed amount. Accepts `2.5`, `2,5` (comma decimal), `.5`,
/// `1/2`, `1 1/2`, `1½`, `1 and a half`, and `half`/`quarter`. Rejects
/// zero, negatives, `1,000` (could be a thousands separator) and anything
/// else; null means "could not read this exactly".
double? parseAmount(String raw) {
  final text = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return null;
  double? value = _wordAmounts[text];
  if (value == null) {
    final mixed = _mixedFraction.firstMatch(text);
    final fraction = _fraction.firstMatch(text);
    final half = _andAHalf.firstMatch(text);
    if (mixed != null) {
      final denominator = double.parse(mixed.group(3)!);
      if (denominator == 0) return null;
      value =
          double.parse(mixed.group(1)!) +
          double.parse(mixed.group(2)!) / denominator;
    } else if (fraction != null) {
      final denominator = double.parse(fraction.group(2)!);
      if (denominator == 0) return null;
      value = double.parse(fraction.group(1)!) / denominator;
    } else if (half != null) {
      value = double.parse(half.group(1)!) + .5;
    } else if (_plainNumber.hasMatch(text)) {
      if (_thousandsLike.hasMatch(text)) return null; // 1,000 vs 1.000?
      value = double.tryParse(text.replaceAll(',', '.'));
    }
  }
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

/// Parses money: `₹1,200`, `Rs 450`, `1,20,000`, `99.50`. Zero is allowed
/// (a dose that cost nothing); negatives and junk are not.
double? parseMoney(String raw) {
  var text = raw.trim().toLowerCase();
  text = text.replaceFirst(RegExp(r'^(₹|rs\.?|inr)\s*'), '');
  text = text.replaceAll(' ', '');
  if (text.isEmpty) return null;
  final grouped = RegExp(r'^\d{1,3}(,\d{2,3})+(\.\d+)?$');
  if (grouped.hasMatch(text)) {
    text = text.replaceAll(',', '');
  } else if (RegExp(r'^\d+,\d{1,2}$').hasMatch(text)) {
    text = text.replaceAll(',', '.');
  }
  if (!RegExp(r'^(\d+(\.\d+)?|\.\d+)$').hasMatch(text)) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite || value < 0) return null;
  return value;
}

/// One logged dose as entered, plus its ml value at logging time.
class DoseAmount {
  const DoseAmount._({
    required this.amount,
    required this.unit,
    required this.amountMl,
    required this.bottleMl,
  });

  /// Validates and normalizes a new entry. Throws [ArgumentError] for zero,
  /// negative, non-finite or absurd values.
  factory DoseAmount.entered(
    double amount,
    DoseUnit unit, {
    required double bottleMl,
  }) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Amount must be greater than zero.');
    }
    if (unit == DoseUnit.bottle && !isValidBottleMl(bottleMl)) {
      throw ArgumentError('Bottle size must be 10–2000 ml.');
    }
    final ml = toMl(amount, unit, bottleMl: bottleMl);
    if (ml != null && ml > maxDoseMl) {
      throw ArgumentError('That is over 20 L. Check the amount and unit.');
    }
    if (ml == null && amount > maxDoseCount) {
      throw ArgumentError('That count is too high. Check the amount.');
    }
    return DoseAmount._(
      amount: amount,
      unit: unit,
      amountMl: ml,
      bottleMl: unit == DoseUnit.bottle ? bottleMl : null,
    );
  }

  /// Reads stored metadata. Never recomputes ml from today's bottle size.
  static DoseAmount? fromMetadata(Map<String, dynamic> metadata) {
    final unit = DoseUnitInfo.fromName(metadata['unit']);
    final amount = metadata['amount'];
    if (unit == null || amount is! num || amount <= 0) return null;
    final ml = metadata['amountMl'];
    final bottle = metadata['bottleMl'];
    return DoseAmount._(
      amount: amount.toDouble(),
      unit: unit,
      amountMl: unit.isVolume && ml is num ? ml.toDouble() : null,
      bottleMl: unit == DoseUnit.bottle && bottle is num
          ? bottle.toDouble()
          : null,
    );
  }

  final double amount;
  final DoseUnit unit;

  /// ml at the time of logging; null for tablets and drinks.
  final double? amountMl;

  /// Bottle size used for the conversion (bottle entries only).
  final double? bottleMl;

  Map<String, dynamic> toMetadata() => {
    'amount': amount,
    'unit': unit.name,
    'amountMl': ?amountMl,
    'bottleMl': ?bottleMl,
  };

  /// e.g. `2.5 bottles · 250 ml`, `330 ml`, `1.5 L · 1,500 ml`, `2 tablets`.
  String get display {
    final entered = '${formatAmount(amount)} ${unit.labelFor(amount)}';
    final ml = amountMl;
    if (ml == null || unit == DoseUnit.ml) return entered;
    return '$entered · ${formatMl(ml)}';
  }
}

/// Up to two decimals, trailing zeros trimmed. Display only.
String formatAmount(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
      : fixed;
}

/// `250 ml`, `7.5 ml`, `1.25 L`. Display only.
String formatMl(double ml) {
  if (ml >= 1000) return '${formatAmount(ml / 1000)} L';
  if (ml < 10) return '${formatAmount((ml * 10).round() / 10)} ml';
  return '${ml.round()} ml';
}

/// Reads an exact quantity from legacy free text: `250ml`, `0.5 L`,
/// `2.5 bottles`, `half a bottle`, `1/2 bottle`, `2 tablets`, `3 drinks`.
/// Anything not matching exactly (e.g. "half a cup", "a lot") returns null
/// and the text is left as it is.
DoseAmount? parseQuantityText(String text, {required double bottleMl}) {
  final match = RegExp(
    r'^\s*(.+?)\s*(ml|mls|millilit(?:re|er)s?|l|ltrs?|lit(?:re|er)s?|bottles?|btls?|drinks?|tablets?|tabs?|pills?)\.?\s*$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  var amountText = match.group(1)!.trim().toLowerCase();
  amountText = amountText.replaceFirst(RegExp(r'\s+(of\s+)?(a|an)$'), '');
  amountText = amountText.replaceFirst(RegExp(r'\s+of$'), '');
  final amount = parseAmount(amountText);
  if (amount == null) return null;
  final unitText = match.group(2)!.toLowerCase();
  final unit = switch (unitText) {
    'ml' || 'mls' => DoseUnit.ml,
    'l' || 'ltr' || 'ltrs' => DoseUnit.litre,
    _ when unitText.startsWith('milli') => DoseUnit.ml,
    _ when unitText.startsWith('lit') => DoseUnit.litre,
    _ when unitText.startsWith('b') => DoseUnit.bottle,
    _ when unitText.startsWith('d') => DoseUnit.drink,
    _ => DoseUnit.tablet,
  };
  try {
    return DoseAmount.entered(amount, unit, bottleMl: bottleMl);
  } on ArgumentError {
    return null;
  }
}

/// A likely unit mix-up, with the correction to offer.
class DoseSanityCheck {
  const DoseSanityCheck({required this.message, this.suggestedUnit});

  final String message;
  final DoseUnit? suggestedUnit;
}

/// Flags entries that are probably the wrong unit, e.g. 250 with "bottles"
/// (25 L at 100 ml) or 0.25 with "ml". Null when the entry looks plausible.
DoseSanityCheck? doseSanityCheck(
  double amount,
  DoseUnit unit, {
  required double bottleMl,
}) {
  final shown = formatAmount(amount);
  switch (unit) {
    case DoseUnit.bottle:
      final ml = amount * bottleMl;
      if (amount >= 20 || ml > 5000) {
        return DoseSanityCheck(
          message:
              '$shown bottles at ${formatMl(bottleMl)} is ${formatMl(ml)}. Did you mean $shown ml?',
          suggestedUnit: DoseUnit.ml,
        );
      }
    case DoseUnit.litre:
      if (amount >= 10) {
        return DoseSanityCheck(
          message:
              '$shown L is ${formatMl(amount * 1000)}. Did you mean $shown ml?',
          suggestedUnit: DoseUnit.ml,
        );
      }
    case DoseUnit.ml:
      if (amount < 1) {
        return DoseSanityCheck(
          message:
              '$shown ml is less than a drop. Did you mean $shown L (${formatMl(amount * 1000)})?',
          suggestedUnit: DoseUnit.litre,
        );
      }
      if (amount < 5 && amount == amount.roundToDouble()) {
        return DoseSanityCheck(
          message:
              '$shown ml is under a teaspoon. Did you mean $shown ${DoseUnit.bottle.labelFor(amount)} (${formatMl(amount * bottleMl)})?',
          suggestedUnit: DoseUnit.bottle,
        );
      }
    case DoseUnit.tablet:
      if (amount > 20) {
        return DoseSanityCheck(
          message: '$shown tablets is a lot. Check the number before saving.',
        );
      }
    case DoseUnit.drink:
      if (amount > 30) {
        return DoseSanityCheck(
          message: '$shown drinks is a lot. Check the number before saving.',
        );
      }
  }
  return null;
}
