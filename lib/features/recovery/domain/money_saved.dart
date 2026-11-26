import 'dart:math' as math;

import '../../../core/utils/formatters.dart';
import 'dose_units.dart';
import 'event_derived_state.dart';
import 'recovery_event.dart';

/// Optional savings target the user is working toward (a "goal jar").
///
/// [photoPath] is a local file on this device. It is stored as a path only
/// — backups stay small, and a missing file simply hides the photo.
class SavingsGoal {
  const SavingsGoal({required this.name, required this.target, this.photoPath});

  final String name;
  final double target;
  final String? photoPath;

  bool get isValid =>
      name.trim().isNotEmpty &&
      name.trim().length <= 80 &&
      target.isFinite &&
      target > 0 &&
      target <= maxRelapseCost;

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'target': target,
    if (photoPath != null && photoPath!.trim().isNotEmpty)
      'photoPath': photoPath!.trim(),
  };

  /// Returns null when the map is missing or unusable, never throws.
  static SavingsGoal? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final target = raw['target'];
    if (name is! String || name.trim().isEmpty || name.trim().length > 80) {
      return null;
    }
    if (target is! num ||
        !target.isFinite ||
        target <= 0 ||
        target > maxRelapseCost) {
      return null;
    }
    final photo = raw['photoPath'];
    return SavingsGoal(
      name: name.trim(),
      target: target.toDouble(),
      photoPath: photo is String && photo.trim().isNotEmpty
          ? photo.trim()
          : null,
    );
  }
}

/// How typical daily spend is derived from a per-bottle price and a usual
/// daily amount, always converted through [bottleMl] into ml first.
double? typicalDailySpend({
  required double? spendPerBottle,
  required double? usualDailyMl,
  required double bottleMl,
}) {
  if (spendPerBottle == null ||
      usualDailyMl == null ||
      !spendPerBottle.isFinite ||
      !usualDailyMl.isFinite ||
      spendPerBottle < 0 ||
      usualDailyMl <= 0 ||
      !isValidBottleMl(bottleMl)) {
    return null;
  }
  return (usualDailyMl / bottleMl) * spendPerBottle;
}

/// Recorded spend on slips that did *not* reset the lean/codeine timer,
/// after [lastDose]. Today that is benzo-only use with a cost; lean, mixed,
/// alcohol and typeless slips reset the timer so they are not in this window.
double otherSubstanceCostsSince({
  required Iterable<RecoveryEvent> events,
  required DateTime lastDose,
}) {
  var total = 0.0;
  for (final event in events) {
    if (event.type != RecoveryEventType.relapse) continue;
    if (!event.timestamp.isAfter(lastDose)) continue;
    if (resetsLeanCleanTimer(event)) continue;
    final cost = event.metadata['cost'];
    if (cost is num && cost.isFinite && cost > 0) {
      total += cost.toDouble();
    }
  }
  return total;
}

/// Money kept since the lean/codeine clean timer started.
class MoneySavedSnapshot {
  const MoneySavedSnapshot({
    required this.currency,
    required this.dailySpend,
    required this.bottleMl,
    required this.cleanDuration,
    required this.grossSaved,
    required this.otherCosts,
    required this.subtractOtherCosts,
    required this.moneySaved,
    this.spendPerBottle,
    this.usualDailyMl,
    this.goal,
  });

  final AppCurrency currency;
  final double dailySpend;
  final double? spendPerBottle;
  final double? usualDailyMl;
  final double bottleMl;
  final Duration cleanDuration;
  final double grossSaved;
  final double otherCosts;
  final bool subtractOtherCosts;
  final double moneySaved;
  final SavingsGoal? goal;

  bool get isSpendSet => dailySpend > 0;
  bool get hasBreakdown =>
      spendPerBottle != null &&
      spendPerBottle! > 0 &&
      usualDailyMl != null &&
      usualDailyMl! > 0;

  /// 0..1+ of the optional goal. Null when there is no goal.
  double? get goalProgress {
    final g = goal;
    if (g == null || g.target <= 0) return null;
    return moneySaved / g.target;
  }

  int? get goalPercent {
    final p = goalProgress;
    if (p == null) return null;
    return (p * 100).floor();
  }

  String format(num value) => money(value, currency: currency);

  /// Short line for the compact home StatCard.
  String get homeDetail {
    if (!isSpendSet) return 'Tap to set a usual day';
    if (subtractOtherCosts && otherCosts > 0) {
      return '${format(dailySpend)} / day, after ${format(otherCosts)} logged';
    }
    return 'At ${format(dailySpend)} a usual day';
  }

  /// Compact widget / glance text. Never names a substance.
  String get widgetKept =>
      isSpendSet && moneySaved >= 0 ? '${format(moneySaved)} kept' : '';

  /// Privacy-safe notification line. Never names a substance.
  String get notificationText {
    if (goal != null && (goalPercent ?? 0) >= 100) {
      return 'You reached a goal.';
    }
    if (isSpendSet && moneySaved > 0) {
      return '${format(moneySaved)} kept so far.';
    }
    return 'Open the app when you have a moment.';
  }

  /// Warm in-app paragraph built only from the user's numbers.
  String get warmCopy {
    if (!isSpendSet) {
      return 'How much did a usual day cost? Set a typical spend and '
          'we will keep a running total — just for you.';
    }
    final days = cleanDuration.inHours / 24;
    final dayLabel = _dayLabel(days);
    final parts = <String>[];
    if (hasBreakdown) {
      parts.add(
        'A usual day was ${_usualAmountPhrase()} at '
        '${format(spendPerBottle!)} a bottle.',
      );
    }
    if (days < 1 / 24) {
      parts.add(
        'The counter starts from your clean time. At '
        '${format(dailySpend)} a usual day, it adds up.',
      );
    } else {
      parts.add(
        '${format(grossSaved)} kept over $dayLabel, at '
        '${format(dailySpend)} a usual day.',
      );
    }
    if (subtractOtherCosts && otherCosts > 0) {
      parts.add(
        'That is ${format(moneySaved)} after setting aside '
        '${format(otherCosts)} you logged on other days.',
      );
    }
    final g = goal;
    if (g != null) {
      final pct = goalPercent ?? 0;
      if (pct >= 100) {
        parts.add(
          '${format(moneySaved)} of ${format(g.target)} toward '
          '${g.name} — you made it.',
        );
      } else {
        parts.add(
          '${format(moneySaved)} of ${format(g.target)} toward '
          '${g.name} — $pct% of the way there.',
        );
      }
    }
    return parts.join(' ');
  }

  String _usualAmountPhrase() {
    final ml = usualDailyMl!;
    final bottles = ml / bottleMl;
    final bottleLabel = (bottles - 1).abs() < 1e-9
        ? '1 bottle'
        : '${_trim(bottles)} bottles';
    if ((bottles * 20).round() / 20 == bottles || bottles >= 0.2) {
      return '$bottleLabel (${formatMl(ml)})';
    }
    return formatMl(ml);
  }

  static String _trim(double value) {
    if ((value - value.round()).abs() < 1e-9) return '${value.round()}';
    final one = value.toStringAsFixed(1);
    return one.endsWith('0') ? value.toStringAsFixed(0) : one;
  }

  static String _dayLabel(double days) {
    if (days < 1) {
      final hours = (days * 24).round().clamp(1, 23);
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    if ((days - days.round()).abs() < 0.05) {
      final n = days.round();
      return n == 1 ? '1 day' : '$n days';
    }
    final one = days.toStringAsFixed(1);
    return '$one days';
  }
}

/// Computes money kept since [lastDose] (the lean/codeine clean timer).
///
/// Benzo-only slips do not move [lastDose]. When [subtractOtherCosts] is
/// true, recorded costs on those (and any future non-resetting) slips after
/// the timer start are taken off the total. Missing spend fields fall back
/// to [dailySpend] so older states keep their existing figure.
MoneySavedSnapshot computeMoneySaved({
  required double dailySpend,
  required double bottleMl,
  required Duration cleanDuration,
  required Iterable<RecoveryEvent> events,
  required DateTime lastDose,
  AppCurrency currency = AppCurrency.inr,
  double? spendPerBottle,
  double? usualDailyMl,
  bool subtractOtherCosts = false,
  SavingsGoal? goal,
}) {
  final derived = typicalDailySpend(
    spendPerBottle: spendPerBottle,
    usualDailyMl: usualDailyMl,
    bottleMl: bottleMl,
  );
  final rate = (derived != null && derived > 0)
      ? derived
      : (dailySpend.isFinite && dailySpend > 0 ? dailySpend : 0.0);
  final days = math.max(0.0, cleanDuration.inHours / 24);
  final gross = days * rate;
  final other = subtractOtherCosts
      ? otherSubstanceCostsSince(events: events, lastDose: lastDose)
      : 0.0;
  return MoneySavedSnapshot(
    currency: currency,
    dailySpend: rate,
    spendPerBottle: spendPerBottle != null && spendPerBottle > 0
        ? spendPerBottle
        : null,
    usualDailyMl: usualDailyMl != null && usualDailyMl > 0
        ? usualDailyMl
        : null,
    bottleMl: bottleMl,
    cleanDuration: cleanDuration,
    grossSaved: gross,
    otherCosts: other,
    subtractOtherCosts: subtractOtherCosts,
    moneySaved: math.max(0.0, gross - other),
    goal: goal,
  );
}

/// True when a string is safe to show on a private widget or notification
/// (no substance names). Used in tests and as a sanity check for copy.
bool isPrivacySafeMoneyCopy(String text) {
  final lower = text.toLowerCase();
  const banned = [
    'lean',
    'codeine',
    'benzo',
    'benzodiazepine',
    'phensedyl',
    'ascoril',
    'corex',
    'alcohol',
    'weed',
    'relapse',
    'dose',
  ];
  return banned.every((word) => !lower.contains(word));
}
