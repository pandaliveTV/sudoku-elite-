import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sudoku/data/daily.dart';
import 'package:sudoku/data/difficulty.dart';
import 'package:sudoku/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('stats, coins and level persist across restarts', () async {
    final s = StorageService();
    await s.init();
    expect(s.firstLaunch, greaterThan(0));
    s.recordStarted(Difficulty.hard);
    s.recordStarted(Difficulty.hard);
    expect(s.recordWin(Difficulty.hard, 300), isTrue);
    expect(s.recordWin(Difficulty.hard, 400), isFalse);
    expect(s.recordWin(Difficulty.hard, 200), isTrue);
    s.addCoins(35);
    s.addXp(150);
    s.markDailyDone('2026-09-01');
    s.saveGame({'difficulty': 'hard', 'elapsed': 12});

    final r = StorageService();
    await r.init();
    final h = r.stats[Difficulty.hard]!;
    expect(h.played, 2);
    expect(h.won, 3);
    expect(h.bestTime, 200);
    expect(h.averageTime, 300);
    expect(h.bestStreak, 3);
    expect(r.coins, 35);
    expect(r.level, 2);
    expect(r.dailyDoneInMonth(2026, 9), 1);
    expect(r.loadGame()!['elapsed'], 12);
    expect(r.bestTimeOverall, 200);
    expect(r.firstLaunch, s.firstLaunch);
  });

  test('loss resets streak; win rate', () async {
    final s = StorageService();
    await s.init();
    for (var k = 0; k < 4; k++) {
      s.recordStarted(Difficulty.easy);
    }
    s.recordWin(Difficulty.easy, 100);
    s.recordLoss(Difficulty.easy);
    final e = s.stats[Difficulty.easy]!;
    expect(e.streak, 0);
    expect(e.bestStreak, 1);
    expect(e.winRate, 0.25);
  });

  test('daily helpers', () {
    final d = DateTime(2026, 2, 7);
    expect(Daily.key(d), '2026-02-07');
    expect(Daily.parse('2026-02-07'), d);
    expect(Daily.seed(d), 20260207);
    expect(Daily.daysInMonth(2026, 2), 28);
    expect(Daily.daysInMonth(2028, 2), 29);
    expect(Daily.difficulty(DateTime(2026, 9, 27)), Difficulty.expert); // Sun
    expect(Daily.trophy(9, 30), Trophy.none);
    expect(Daily.trophy(10, 30), Trophy.bronze);
    expect(Daily.trophy(20, 30), Trophy.silver);
    expect(Daily.trophy(30, 30), Trophy.gold);
  });
}
