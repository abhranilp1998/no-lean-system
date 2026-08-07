import 'package:intl/intl.dart';

String money(num value) => NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
).format(value);

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String formatDuration(Duration duration, {bool compact = false}) {
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24).toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return compact
      ? '${days}d ${hours}h ${minutes}m'
      : '$days days, $hours:$minutes:$seconds';
}
