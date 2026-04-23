// lib/core/utils/currency_formatter.dart
import 'package:intl/intl.dart';
import 'package:gatekeepeer/core/constants/app_constants.dart';

class CurrencyFormatter {
  static final _formatter = NumberFormat.currency(
    locale: 'en_NG',
    symbol: AppConstants.currencySymbol,
    decimalDigits: 2,
  );

  static final _compact = NumberFormat.compactCurrency(
    locale: 'en_NG',
    symbol: AppConstants.currencySymbol,
    decimalDigits: 1,
  );

  static final _noDecimal = NumberFormat.currency(
    locale: 'en_NG',
    symbol: AppConstants.currencySymbol,
    decimalDigits: 0,
  );

  /// Format as ₦15,000.00
  static String format(double amount) => _formatter.format(amount);

  /// Format as ₦15K
  static String compact(double amount) => _compact.format(amount);

  /// Format as ₦15,000
  static String formatNoDecimal(double amount) => _noDecimal.format(amount);

  /// Parse ₦15,000.00 → 15000.0
  static double parse(String value) {
    final cleaned = value.replaceAll(RegExp(r'[₦,\s]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
}
