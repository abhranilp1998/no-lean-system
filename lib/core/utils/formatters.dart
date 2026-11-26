import 'package:intl/intl.dart';

/// A display currency for spend and money-saved figures.
///
/// [inr] is the default so existing backups and screens keep showing ₹
/// until the user picks something else.
class AppCurrency {
  const AppCurrency({
    required this.code,
    required this.symbol,
    required this.locale,
    required this.name,
  });

  final String code;
  final String symbol;
  final String locale;
  final String name;

  static const inr = AppCurrency(
    code: 'INR',
    symbol: '₹',
    locale: 'en_IN',
    name: 'Indian rupee',
  );
  static const usd = AppCurrency(
    code: 'USD',
    symbol: r'$',
    locale: 'en_US',
    name: 'US dollar',
  );
  static const eur = AppCurrency(
    code: 'EUR',
    symbol: '€',
    locale: 'en_IE',
    name: 'Euro',
  );
  static const gbp = AppCurrency(
    code: 'GBP',
    symbol: '£',
    locale: 'en_GB',
    name: 'British pound',
  );
  static const aud = AppCurrency(
    code: 'AUD',
    symbol: r'A$',
    locale: 'en_AU',
    name: 'Australian dollar',
  );
  static const cad = AppCurrency(
    code: 'CAD',
    symbol: r'C$',
    locale: 'en_CA',
    name: 'Canadian dollar',
  );
  static const sgd = AppCurrency(
    code: 'SGD',
    symbol: r'S$',
    locale: 'en_SG',
    name: 'Singapore dollar',
  );
  static const aed = AppCurrency(
    code: 'AED',
    symbol: 'AED ',
    locale: 'en_AE',
    name: 'UAE dirham',
  );
  static const bdt = AppCurrency(
    code: 'BDT',
    symbol: '৳',
    locale: 'en_US',
    name: 'Bangladeshi taka',
  );
  static const npr = AppCurrency(
    code: 'NPR',
    symbol: 'NPR ',
    locale: 'en_IN',
    name: 'Nepalese rupee',
  );
  static const pkr = AppCurrency(
    code: 'PKR',
    symbol: '₨',
    locale: 'en_US',
    name: 'Pakistani rupee',
  );
  static const php = AppCurrency(
    code: 'PHP',
    symbol: '₱',
    locale: 'en_PH',
    name: 'Philippine peso',
  );
  static const jpy = AppCurrency(
    code: 'JPY',
    symbol: '¥',
    locale: 'ja',
    name: 'Japanese yen',
  );
  static const myr = AppCurrency(
    code: 'MYR',
    symbol: 'RM',
    locale: 'en_MY',
    name: 'Malaysian ringgit',
  );
  static const thb = AppCurrency(
    code: 'THB',
    symbol: '฿',
    locale: 'th',
    name: 'Thai baht',
  );

  static const supported = <AppCurrency>[
    inr,
    usd,
    eur,
    gbp,
    aud,
    cad,
    sgd,
    aed,
    bdt,
    npr,
    pkr,
    php,
    jpy,
    myr,
    thb,
  ];

  /// Unknown or missing codes fall back to rupees, never throw.
  static AppCurrency fromCode(Object? code) {
    if (code is! String || code.trim().isEmpty) return inr;
    final needle = code.trim().toUpperCase();
    return supported.where((c) => c.code == needle).firstOrElse();
  }

  String format(num value) => NumberFormat.currency(
    locale: locale,
    symbol: symbol,
    decimalDigits: 0,
  ).format(value);
}

extension _FirstOrInr on Iterable<AppCurrency> {
  AppCurrency firstOrElse() => isEmpty ? AppCurrency.inr : first;
}

/// Formats [value] in [currency]. Defaults to ₹ so existing call sites and
/// tests keep the same output until a currency is passed.
String money(num value, {AppCurrency currency = AppCurrency.inr}) =>
    currency.format(value);

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
