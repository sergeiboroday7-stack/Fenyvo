class MessageChronology {
  static void sort(List<Map<String, dynamic>> messages) {
    int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
      final aTime = DateTime.tryParse(a['time']?.toString() ?? '');
      final bTime = DateTime.tryParse(b['time']?.toString() ?? '');
      if (aTime != null && bTime != null) {
        final byTime = aTime.compareTo(bTime);
        if (byTime != 0) return byTime;
      } else if (aTime != null) {
        return -1;
      } else if (bTime != null) {
        return 1;
      }
      return 0;
    }

    final indexed = messages.asMap().entries.toList();
    indexed.sort((a, b) {
      final result = compare(a.value, b.value);
      return result != 0 ? result : a.key.compareTo(b.key);
    });
    messages
      ..clear()
      ..addAll(indexed.map((entry) => entry.value));
  }
}
