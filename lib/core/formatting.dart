import 'package:intl/intl.dart';

/// A date and time the way people read them, such as "Sep 15, 2026 7:45 AM",
/// in the phone's local time zone.
///
/// Backup and sync screens used to print `DateTime.toLocal()` directly,
/// which shows "2026-09-15 07:45:12.431".
String formatDateTime(DateTime time) =>
    DateFormat.yMMMd().add_jm().format(time.toLocal());
