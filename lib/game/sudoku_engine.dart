import 'dart:math';

import '../data/difficulty.dart';

/// Board geometry helpers shared by the solver, generator and UI.
///
/// A board is a flat `List<int>` of 81 cells in row-major order where `0`
/// means empty and `1..9` are digits.
class Board {
  Board._();

  static final List<int> rowOf = List.generate(81, (i) => i ~/ 9);
  static final List<int> colOf = List.generate(81, (i) => i % 9);
  static final List<int> boxOf = List.generate(
    81,
    (i) => (i ~/ 27) * 3 + (i % 9) ~/ 3,
  );

  /// The 27 units: 9 rows, 9 columns, 9 boxes.
  static final List<List<int>> units = [
    for (var r = 0; r < 9; r++) [for (var c = 0; c < 9; c++) r * 9 + c],
    for (var c = 0; c < 9; c++) [for (var r = 0; r < 9; r++) r * 9 + c],
    for (var b = 0; b < 9; b++)
      [
        for (var k = 0; k < 9; k++)
          ((b ~/ 3) * 3 + k ~/ 3) * 9 + (b % 3) * 3 + k % 3,
      ],
  ];

  /// For every cell, the 20 other cells sharing its row, column or box.
  static final List<List<int>> peers = List.generate(81, (i) {
    final s = <int>{};
    for (final u in [
      units[rowOf[i]],
      units[9 + colOf[i]],
      units[18 + boxOf[i]],
    ]) {
      s.addAll(u);
    }
    s.remove(i);
    return s.toList(growable: false);
  });

  /// Number of set bits for every 10-bit candidate mask.
  static final List<int> bitCount = List.generate(1024, (m) {
    var c = 0;
    for (var x = m; x != 0; x &= x - 1) {
      c++;
    }
    return c;
  });

  static const int allDigits = 0x3FE; // bits 1..9

  /// True when [digit] can be placed at [index] without clashing with a peer.
  static bool canPlace(List<int> grid, int index, int digit) {
    for (final p in peers[index]) {
      if (grid[p] == digit) return false;
    }
    return true;
  }
}

/// Backtracking Sudoku solver using bitmasks and "fewest candidates first".
class SudokuSolver {
  SudokuSolver._();

  /// Returns a solved copy of [grid], or null when it has no solution.
  /// When [random] is given, candidate digits are tried in random order
  /// (used by the generator to build random full grids).
  static List<int>? solve(List<int> grid, {Random? random}) {
    final s = _Search(List.of(grid), limit: 1, random: random);
    if (!s.init()) return null;
    s.run();
    return s.firstSolution;
  }

  /// Counts solutions of [grid], stopping as soon as [limit] is reached.
  static int countSolutions(List<int> grid, {int limit = 2}) {
    final s = _Search(List.of(grid), limit: limit);
    if (!s.init()) return 0;
    s.run();
    return s.count;
  }

  static bool hasUniqueSolution(List<int> grid) =>
      countSolutions(grid, limit: 2) == 1;

  /// Tries to finish [grid] with human "single" techniques only.
  /// Returns true when the whole grid gets filled.
  static bool solvableWithSingles(List<int> grid, {bool hidden = true}) {
    final g = List.of(grid);
    var progress = true;
    while (progress) {
      progress = false;
      var empty = 0;
      // Naked singles.
      for (var i = 0; i < 81; i++) {
        if (g[i] != 0) continue;
        empty++;
        final m = _candidates(g, i);
        final n = Board.bitCount[m];
        if (n == 0) return false;
        if (n == 1) {
          g[i] = _lowestDigit(m);
          progress = true;
        }
      }
      if (empty == 0) return true;
      if (progress || !hidden) continue;
      // Hidden singles.
      for (final unit in Board.units) {
        for (var d = 1; d <= 9; d++) {
          var spot = -1;
          var count = 0;
          var present = false;
          for (final i in unit) {
            if (g[i] == d) {
              present = true;
              break;
            }
            if (g[i] == 0 && (_candidates(g, i) & (1 << d)) != 0) {
              count++;
              spot = i;
            }
          }
          if (!present && count == 1) {
            g[spot] = d;
            progress = true;
          }
        }
      }
    }
    return !g.contains(0);
  }

  static int _candidates(List<int> g, int i) {
    var used = 0;
    for (final p in Board.peers[i]) {
      used |= 1 << g[p];
    }
    return Board.allDigits & ~used;
  }

  static int _lowestDigit(int mask) {
    for (var d = 1; d <= 9; d++) {
      if (mask & (1 << d) != 0) return d;
    }
    return 0;
  }
}

class _Search {
  _Search(this.g, {required this.limit, this.random});

  final List<int> g;
  final int limit;
  final Random? random;
  final rows = List<int>.filled(9, 0);
  final cols = List<int>.filled(9, 0);
  final boxes = List<int>.filled(9, 0);
  int count = 0;
  List<int>? firstSolution;

  bool init() {
    for (var i = 0; i < 81; i++) {
      final v = g[i];
      if (v == 0) continue;
      if (v < 0 || v > 9) return false;
      final bit = 1 << v;
      final r = Board.rowOf[i], c = Board.colOf[i], b = Board.boxOf[i];
      if ((rows[r] | cols[c] | boxes[b]) & bit != 0) return false;
      rows[r] |= bit;
      cols[c] |= bit;
      boxes[b] |= bit;
    }
    return true;
  }

  void run() {
    if (count >= limit) return;
    var best = -1;
    var bestMask = 0;
    var bestN = 10;
    for (var i = 0; i < 81; i++) {
      if (g[i] != 0) continue;
      final m =
          Board.allDigits &
          ~(rows[Board.rowOf[i]] |
              cols[Board.colOf[i]] |
              boxes[Board.boxOf[i]]);
      final n = Board.bitCount[m];
      if (n == 0) return; // dead end
      if (n < bestN) {
        best = i;
        bestMask = m;
        bestN = n;
        if (n == 1) break;
      }
    }
    if (best == -1) {
      count++;
      firstSolution ??= List.of(g);
      return;
    }
    final digits = <int>[
      for (var d = 1; d <= 9; d++)
        if (bestMask & (1 << d) != 0) d,
    ];
    if (random != null) digits.shuffle(random);
    final r = Board.rowOf[best], c = Board.colOf[best], b = Board.boxOf[best];
    for (final d in digits) {
      final bit = 1 << d;
      g[best] = d;
      rows[r] |= bit;
      cols[c] |= bit;
      boxes[b] |= bit;
      run();
      g[best] = 0;
      rows[r] &= ~bit;
      cols[c] &= ~bit;
      boxes[b] &= ~bit;
      if (count >= limit) return;
    }
  }
}

/// A generated puzzle together with its (unique) solution.
class Puzzle {
  const Puzzle({
    required this.givens,
    required this.solution,
    required this.difficulty,
  });

  final List<int> givens;
  final List<int> solution;
  final Difficulty difficulty;

  int get clueCount => givens.where((v) => v != 0).length;
}

/// Builds puzzles that always have exactly one solution.
class SudokuGenerator {
  SudokuGenerator._();

  /// Maximum full regenerations when a candidate puzzle misses the
  /// difficulty's technique requirement.
  static const _maxAttempts = 30;

  /// Generates a puzzle for [difficulty]. The same [seed] always yields the
  /// same puzzle (used by the daily challenge).
  static Puzzle generate(Difficulty difficulty, {int? seed}) {
    final random = Random(seed ?? DateTime.now().microsecondsSinceEpoch);
    Puzzle? fallback;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final p = _attempt(difficulty, random);
      if (difficulty.technique != SolveTechnique.beyondSingles ||
          !SudokuSolver.solvableWithSingles(p.givens)) {
        return p;
      }
      if (fallback == null || p.clueCount < fallback.clueCount) fallback = p;
    }
    return fallback!;
  }

  static Puzzle _attempt(Difficulty d, Random random) {
    final solution = SudokuSolver.solve(List.filled(81, 0), random: random)!;
    final grid = List.of(solution);
    final order = List.generate(81, (i) => i)..shuffle(random);
    var clues = 81;
    for (final i in order) {
      if (clues <= d.targetClues) break;
      if (grid[i] == 0) continue;
      final j = d.symmetric ? 80 - i : i;
      final vi = grid[i], vj = grid[j];
      grid[i] = 0;
      grid[j] = 0;
      final removed = i == j ? 1 : 2;
      if (_acceptable(grid, d)) {
        clues -= removed;
      } else {
        grid[i] = vi;
        grid[j] = vj;
      }
    }
    return Puzzle(givens: grid, solution: solution, difficulty: d);
  }

  static bool _acceptable(List<int> grid, Difficulty d) {
    if (!SudokuSolver.hasUniqueSolution(grid)) return false;
    switch (d.technique) {
      case SolveTechnique.nakedSingles:
        return SudokuSolver.solvableWithSingles(grid, hidden: false);
      case SolveTechnique.singles:
        return SudokuSolver.solvableWithSingles(grid);
      case SolveTechnique.any:
      case SolveTechnique.beyondSingles:
        return true;
    }
  }
}

/// Entry point for `compute()` so generation runs off the UI isolate.
/// [args] is `(difficultyKey, seed)`; returns `[givens..., solution...]`.
List<int> generatePuzzleIsolate((String, int?) args) {
  final p = SudokuGenerator.generate(
    Difficulty.fromKey(args.$1),
    seed: args.$2,
  );
  return [...p.givens, ...p.solution];
}
