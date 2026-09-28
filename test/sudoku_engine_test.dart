import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku/data/difficulty.dart';
import 'package:sudoku/game/sudoku_engine.dart';

List<int> parse(String s) =>
    s.split('').map((c) => c == '.' ? 0 : int.parse(c)).toList();

bool isValidSolution(List<int> g) {
  if (g.length != 81 || g.contains(0)) return false;
  for (final unit in Board.units) {
    if (unit.map((i) => g[i]).toSet().length != 9) return false;
  }
  return true;
}

void main() {
  // A well-known puzzle with a unique solution.
  const puzzle =
      '53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79';
  const solution =
      '534678912672195348198342567859761423426853791713924856961537284287419635345286179';

  group('Board', () {
    test('geometry tables are consistent', () {
      expect(Board.units.length, 27);
      for (final u in Board.units) {
        expect(u.toSet().length, 9);
      }
      for (var i = 0; i < 81; i++) {
        expect(Board.peers[i].length, 20);
        expect(Board.peers[i], isNot(contains(i)));
      }
      expect(Board.boxOf[0], 0);
      expect(Board.boxOf[80], 8);
      expect(Board.boxOf[4 * 9 + 4], 4);
    });

    test('canPlace detects clashes', () {
      final g = parse(puzzle);
      expect(Board.canPlace(g, 2, 5), isFalse); // 5 already in row
      expect(Board.canPlace(g, 2, 4), isTrue);
    });
  });

  group('SudokuSolver', () {
    test('solves a classic puzzle', () {
      expect(SudokuSolver.solve(parse(puzzle)), parse(solution));
    });

    test('does not modify its input', () {
      final g = parse(puzzle);
      SudokuSolver.solve(g);
      expect(g, parse(puzzle));
    });

    test('reports uniqueness', () {
      expect(SudokuSolver.countSolutions(parse(puzzle)), 1);
      expect(SudokuSolver.hasUniqueSolution(parse(puzzle)), isTrue);
    });

    test('detects multiple solutions', () {
      final empty = List.filled(81, 0);
      expect(SudokuSolver.countSolutions(empty), 2);
      expect(SudokuSolver.hasUniqueSolution(empty), isFalse);
    });

    test('detects unsolvable / invalid grids', () {
      final g = parse(puzzle);
      g[2] = 5; // duplicate 5 in first row
      expect(SudokuSolver.solve(g), isNull);
      expect(SudokuSolver.countSolutions(g), 0);
    });

    test('random full grid is valid', () {
      final g = SudokuSolver.solve(List.filled(81, 0));
      expect(isValidSolution(g!), isTrue);
    });

    test('singles solver finishes an easy puzzle', () {
      expect(SudokuSolver.solvableWithSingles(parse(puzzle)), isTrue);
    });
  });

  group('SudokuGenerator', () {
    for (final d in Difficulty.values) {
      test('${d.key}: unique, consistent and within clue budget', () {
        for (var seed = 0; seed < 8; seed++) {
          final p = SudokuGenerator.generate(d, seed: seed);
          expect(isValidSolution(p.solution), isTrue);
          expect(SudokuSolver.hasUniqueSolution(p.givens), isTrue);
          expect(SudokuSolver.solve(p.givens), p.solution);
          for (var i = 0; i < 81; i++) {
            if (p.givens[i] != 0) expect(p.givens[i], p.solution[i]);
          }
          expect(p.clueCount, greaterThanOrEqualTo(17));
          expect(p.clueCount, lessThanOrEqualTo(d.targetClues + 6));
        }
      });
    }

    test('easy needs only naked singles, medium only singles', () {
      for (var seed = 0; seed < 5; seed++) {
        final e = SudokuGenerator.generate(Difficulty.easy, seed: seed);
        expect(
          SudokuSolver.solvableWithSingles(e.givens, hidden: false),
          isTrue,
        );
        final m = SudokuGenerator.generate(Difficulty.medium, seed: seed);
        expect(SudokuSolver.solvableWithSingles(m.givens), isTrue);
      }
    });

    test('expert is not solvable with singles alone', () {
      for (var seed = 0; seed < 5; seed++) {
        final x = SudokuGenerator.generate(Difficulty.expert, seed: seed);
        expect(SudokuSolver.solvableWithSingles(x.givens), isFalse);
      }
    });

    test('difficulty ordering by average clue count', () {
      double avg(Difficulty d) =>
          List.generate(
            10,
            (s) => SudokuGenerator.generate(d, seed: 100 + s).clueCount,
          ).reduce((a, b) => a + b) /
          10;
      final e = avg(Difficulty.easy);
      final m = avg(Difficulty.medium);
      final h = avg(Difficulty.hard);
      final x = avg(Difficulty.expert);
      expect(e, greaterThan(m));
      expect(m, greaterThan(h));
      expect(h, greaterThan(x));
    });

    test('same seed gives the same puzzle (daily challenge)', () {
      final a = SudokuGenerator.generate(Difficulty.hard, seed: 20260928);
      final b = SudokuGenerator.generate(Difficulty.hard, seed: 20260928);
      final c = SudokuGenerator.generate(Difficulty.hard, seed: 20260929);
      expect(a.givens, b.givens);
      expect(a.solution, b.solution);
      expect(a.givens, isNot(c.givens));
    });

    test('isolate entry point returns givens + solution', () {
      final flat = generatePuzzleIsolate(('medium', 42));
      expect(flat.length, 162);
      final p = SudokuGenerator.generate(Difficulty.medium, seed: 42);
      expect(flat.sublist(0, 81), p.givens);
      expect(flat.sublist(81), p.solution);
    });
  });
}
