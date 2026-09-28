import 'difficulty.dart';

/// Deterministic daily-challenge helpers: every player gets the same puzzle
/// for the same calendar day.
class Daily {
  Daily._();

  /// Earliest selectable month in the calendar.
  static final DateTime firstDay = DateTime(2026, 1, 1);

  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime parse(String key) {
    final p = key.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static int seed(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Difficulty rotates through the week (Mon = 1 … Sun = 7).
  static Difficulty difficulty(DateTime d) => const {
    DateTime.monday: Difficulty.easy,
    DateTime.tuesday: Difficulty.medium,
    DateTime.wednesday: Difficulty.medium,
    DateTime.thursday: Difficulty.hard,
    DateTime.friday: Difficulty.medium,
    DateTime.saturday: Difficulty.hard,
    DateTime.sunday: Difficulty.expert,
  }[d.weekday]!;

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// Monthly trophy tier from the number of completed days.
  static Trophy trophy(int completed, int daysInMonth) {
    if (completed >= daysInMonth) return Trophy.gold;
    if (completed >= 20) return Trophy.silver;
    if (completed >= 10) return Trophy.bronze;
    return Trophy.none;
  }

  /// Bonus coins for finishing a daily challenge.
  static const bonusCoins = 25;
}

enum Trophy { none, bronze, silver, gold }
