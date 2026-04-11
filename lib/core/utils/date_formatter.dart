// lib/core/utils/date_formatter.dart
import 'package:intl/intl.dart';

class DateFormatter {
  static final _date = DateFormat('MMM dd, yyyy');
  static final _dateTime = DateFormat('MMM dd, yyyy · hh:mm a');
  static final _time = DateFormat('hh:mm a');
  static final _short = DateFormat('dd MMM');
  static final _monthYear = DateFormat('MM / yy');
  static final _iso = DateFormat('dd.MM.yyyy — HH:mm:ss');

  static String formatDate(DateTime dt) => _date.format(dt);
  static String formatDateTime(DateTime dt) => _dateTime.format(dt);
  static String formatTime(DateTime dt) => _time.format(dt);
  static String formatShort(DateTime dt) => _short.format(dt);
  static String formatMonthYear(DateTime dt) => _monthYear.format(dt);
  static String formatIso(DateTime dt) => _iso.format(dt);

  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatShort(dt);
  }
}
