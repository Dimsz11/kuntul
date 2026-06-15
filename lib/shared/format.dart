import 'package:intl/intl.dart';

/// Locale-aware date formatting that never throws.
///
/// `DateFormat.yMMMd(locale)` requires `intl` locale data to be initialized for
/// non-`en` locales (e.g. via `initializeDateFormatting('ar')`); without it,
/// the constructor throws `LocaleDataException`. This helper tries the
/// requested locale, then falls back to the default (`en`) format so a missing
/// locale dataset can't crash a screen.
String formatDate(DateTime date, String locale) {
  try {
    return DateFormat.yMMMd(locale).format(date);
  } catch (_) {
    return DateFormat.yMMMd().format(date);
  }
}
