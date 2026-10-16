/// Money display — `src/lib/currency.ts` (DRAIS LongTerm), in Dart.
///
/// One formatter for every amount on the phone, producing the web's output
/// character for character: `UGX 1,500,000`, `$ 12.50`. Display only — an
/// amount is never converted between currencies.
library;

/// A currency's display rules — `CurrencyConfig`.
class CurrencyConfig {
  /// Creates a config.
  const CurrencyConfig({
    required this.code,
    required this.symbol,
    required this.decimals,
    this.suffix = false,
  });

  /// ISO-style code.
  final String code;

  /// What is printed.
  final String symbol;

  /// Fraction digits.
  final int decimals;

  /// Symbol after the number rather than before.
  final bool suffix;
}

/// `DEFAULT_CURRENCY`.
const String defaultCurrency = 'UGX';

/// `CURRENCIES`.
const Map<String, CurrencyConfig> currencies = <String, CurrencyConfig>{
  'UGX': CurrencyConfig(code: 'UGX', symbol: 'UGX', decimals: 0),
  'USD': CurrencyConfig(code: 'USD', symbol: r'$', decimals: 2),
  'KES': CurrencyConfig(code: 'KES', symbol: 'KSh', decimals: 0),
  'TZS': CurrencyConfig(code: 'TZS', symbol: 'TSh', decimals: 0),
  'RWF': CurrencyConfig(code: 'RWF', symbol: 'RWF', decimals: 0),
  'SSP': CurrencyConfig(code: 'SSP', symbol: 'SSP', decimals: 2),
  'EUR': CurrencyConfig(code: 'EUR', symbol: '€', decimals: 2),
  'GBP': CurrencyConfig(code: 'GBP', symbol: '£', decimals: 2),
};

/// `getCurrencyConfig()` — an unknown code is its own symbol, no decimals.
CurrencyConfig currencyConfig(String? code) {
  final String c = (code == null || code.isEmpty ? defaultCurrency : code)
      .toUpperCase();
  return currencies[c] ?? CurrencyConfig(code: c, symbol: c, decimals: 0);
}

/// `formatCurrency()`.
///
/// Mirrors `toLocaleString('en-US', {min/maxFractionDigits})`: comma
/// thousands, a dot before the fraction, and halves rounded away from zero
/// (ECMA-402's default `halfExpand`).
String formatCurrency(num? amount, [String? code]) {
  final CurrencyConfig cfg = currencyConfig(code);
  final num n = (amount == null || !amount.isFinite) ? 0 : amount;

  final num scale = _pow10(cfg.decimals);
  final num rounded = (n.abs() * scale).round() / scale;
  final String fixed = rounded.toStringAsFixed(cfg.decimals);
  final List<String> parts = fixed.split('.');
  final String grouped = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (Match _) => ',',
  );
  final bool negative = n < 0 && rounded != 0;
  final String number =
      '${negative ? '-' : ''}$grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
  return cfg.suffix ? '$number ${cfg.symbol}' : '${cfg.symbol} $number';
}

num _pow10(int d) {
  num v = 1;
  for (int i = 0; i < d; i++) {
    v *= 10;
  }
  return v;
}
