import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/difficulty.dart';

/// Per-difficulty statistics.
class DifficultyStats {
  DifficultyStats({
    this.played = 0,
    this.won = 0,
    this.bestTime = 0,
    this.totalTime = 0,
    this.streak = 0,
    this.bestStreak = 0,
  });

  int played;
  int won;

  /// Best winning time in seconds (0 = none yet).
  int bestTime;

  /// Sum of winning times, for the average.
  int totalTime;
  int streak;
  int bestStreak;

  double get winRate => played == 0 ? 0 : won / played;
  int get averageTime => won == 0 ? 0 : totalTime ~/ won;

  Map<String, dynamic> toJson() => {
    'p': played,
    'w': won,
    'b': bestTime,
    't': totalTime,
    's': streak,
    'bs': bestStreak,
  };

  factory DifficultyStats.fromJson(Map<String, dynamic> j) => DifficultyStats(
    played: j['p'] as int? ?? 0,
    won: j['w'] as int? ?? 0,
    bestTime: j['b'] as int? ?? 0,
    totalTime: j['t'] as int? ?? 0,
    streak: j['s'] as int? ?? 0,
    bestStreak: j['bs'] as int? ?? 0,
  );
}

/// Persists progress (level, coins, stats, settings, saved game, daily
/// challenge history) locally with shared_preferences.
class StorageService extends ChangeNotifier {
  StorageService([SharedPreferences? prefs]) : _prefsOverride = prefs;

  final SharedPreferences? _prefsOverride;
  late SharedPreferences _p;

  int coins = 0;
  int xp = 0;
  bool muted = false;
  bool vibration = true;
  bool highlightSame = true;
  bool adsRemoved = false;

  /// 'system', 'ar' or 'en'.
  String language = 'system';

  /// Milliseconds since epoch of the very first launch.
  int firstLaunch = 0;

  final Map<Difficulty, DifficultyStats> stats = {
    for (final d in Difficulty.values) d: DifficultyStats(),
  };

  /// Completed daily challenges as `yyyy-mm-dd` keys.
  Set<String> dailyDone = {};

  /// JSON of the game in progress, if any.
  String? savedGame;

  static const xpPerLevel = 100;
  int get level => 1 + xp ~/ xpPerLevel;
  double get levelProgress => (xp % xpPerLevel) / xpPerLevel;

  /// Best winning time over all difficulties (the "high score").
  int get bestTimeOverall => stats.values
      .map((s) => s.bestTime)
      .where((t) => t > 0)
      .fold(0, (a, b) => a == 0 || b < a ? b : a);

  bool get hasSavedGame => savedGame != null;

  Future<void> init() async {
    _p = _prefsOverride ?? await SharedPreferences.getInstance();
    coins = _p.getInt('coins') ?? 0;
    xp = _p.getInt('xp') ?? 0;
    muted = _p.getBool('muted') ?? false;
    vibration = _p.getBool('vibration') ?? true;
    highlightSame = _p.getBool('highlightSame') ?? true;
    adsRemoved = _p.getBool('adsRemoved') ?? false;
    language = _p.getString('language') ?? 'system';
    dailyDone = (_p.getStringList('dailyDone') ?? const []).toSet();
    savedGame = _p.getString('savedGame');
    for (final d in Difficulty.values) {
      final raw = _p.getString('stats_${d.key}');
      if (raw != null) {
        stats[d] = DifficultyStats.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    }
    firstLaunch = _p.getInt('firstLaunch') ?? 0;
    if (firstLaunch == 0) {
      firstLaunch = DateTime.now().millisecondsSinceEpoch;
      await _p.setInt('firstLaunch', firstLaunch);
    }
  }

  // ------------------------------------------------------------ progress

  void addCoins(int n) {
    coins += n;
    _p.setInt('coins', coins);
    notifyListeners();
  }

  void addXp(int n) {
    xp += n;
    _p.setInt('xp', xp);
    notifyListeners();
  }

  /// Counts a newly started classic game (so abandoned games lower the
  /// win rate, like most Sudoku apps).
  void recordStarted(Difficulty d) {
    stats[d]!.played++;
    _saveStats(d);
  }

  /// Returns true when [seconds] is a new best time.
  bool recordWin(Difficulty d, int seconds) {
    final s = stats[d]!;
    s.won++;
    s.totalTime += seconds;
    s.streak++;
    if (s.streak > s.bestStreak) s.bestStreak = s.streak;
    final record = s.bestTime == 0 || seconds < s.bestTime;
    if (record) s.bestTime = seconds;
    _saveStats(d);
    return record;
  }

  void recordLoss(Difficulty d) {
    stats[d]!.streak = 0;
    _saveStats(d);
  }

  void _saveStats(Difficulty d) {
    _p.setString('stats_${d.key}', jsonEncode(stats[d]!.toJson()));
    notifyListeners();
  }

  void resetStats() {
    for (final d in Difficulty.values) {
      stats[d] = DifficultyStats();
      _p.remove('stats_${d.key}');
    }
    notifyListeners();
  }

  void markDailyDone(String dateKey) {
    if (!dailyDone.add(dateKey)) return;
    _p.setStringList('dailyDone', dailyDone.toList());
    notifyListeners();
  }

  int dailyDoneInMonth(int year, int month) {
    final prefix =
        '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-';
    return dailyDone.where((k) => k.startsWith(prefix)).length;
  }

  // ------------------------------------------------------------ saved game

  void saveGame(Map<String, dynamic> json) {
    final wasEmpty = savedGame == null;
    savedGame = jsonEncode(json);
    _p.setString('savedGame', savedGame!);
    // Only the "Continue" button cares, so avoid notifying on every move.
    if (wasEmpty) notifyListeners();
  }

  Map<String, dynamic>? loadGame() {
    final raw = savedGame;
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      clearSavedGame();
      return null;
    }
  }

  void clearSavedGame() {
    if (savedGame == null) return;
    savedGame = null;
    _p.remove('savedGame');
    notifyListeners();
  }

  // ------------------------------------------------------------ settings

  void setMuted(bool v) {
    muted = v;
    _p.setBool('muted', v);
    notifyListeners();
  }

  void setVibration(bool v) {
    vibration = v;
    _p.setBool('vibration', v);
    notifyListeners();
  }

  void setHighlightSame(bool v) {
    highlightSame = v;
    _p.setBool('highlightSame', v);
    notifyListeners();
  }

  void setLanguage(String v) {
    language = v;
    _p.setString('language', v);
    notifyListeners();
  }

  void setAdsRemoved(bool v) {
    adsRemoved = v;
    _p.setBool('adsRemoved', v);
    notifyListeners();
  }
}
