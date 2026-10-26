/// Compares calendar dates without considering time of day.
///
/// Both DateTime values must use the same intended timezone.
bool isSameMessageCalendarDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

/// Parses an existing message timestamp into the device-local timezone.
/// Returns null for missing or invalid values.
DateTime? parseMessageLocalDate(dynamic timeData) {
  if (timeData == null) {
    return null;
  }

  try {
    return DateTime.parse(timeData.toString()).toLocal();
  } catch (_) {
    return null;
  }
}