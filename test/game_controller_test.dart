import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku/data/difficulty.dart';
import 'package:sudoku/game/game_controller.dart';
import 'package:sudoku/game/sudoku_engine.dart';

void main() {
  late GameController g;

  int firstEmpty() => g.values.indexOf(0);
  int wrongDigit(int i) => g.solution[i] % 9 + 1;

  setUp(() {
    g = GameController.fromPuzzle(
      SudokuGenerator.generate(Difficulty.medium, seed: 7),
    );
  });

  tearDown(() => g.dispose());

  test('correct input is placed and locked', () {
    final i = firstEmpty();
    g.select(i);
    expect(g.input(g.solution[i]), InputResult.placed);
    expect(g.values[i], g.solution[i]);
    expect(g.input(wrongDigit(i)), InputResult.ignored);
    expect(g.erase(), isFalse);
  });

  test('givens cannot be changed', () {
    final i = g.givens.indexWhere((v) => v != 0);
    g.select(i);
    expect(g.input(wrongDigit(i)), InputResult.ignored);
    expect(g.erase(), isFalse);
  });

  test('three mistakes lose, second chance revives once', () {
    final i = firstEmpty();
    g.select(i);
    final wrong = [
      for (var d = 1; d <= 9; d++)
        if (d != g.solution[i]) d,
    ];
    expect(g.input(wrong[0]), InputResult.mistake);
    expect(g.input(wrong[1]), InputResult.mistake);
    expect(g.input(wrong[2]), InputResult.lost);
    expect(g.status, GameStatus.lost);
    expect(g.canRevive, isTrue);
    expect(g.revive(), isTrue);
    expect(g.status, GameStatus.playing);
    expect(g.mistakes, GameController.maxMistakes - 1);
    expect(g.input(wrong[3]), InputResult.lost);
    expect(g.canRevive, isFalse);
    expect(g.revive(), isFalse);
  });

  test('erase clears a wrong digit and undo restores it', () {
    final i = firstEmpty();
    g.select(i);
    g.input(wrongDigit(i));
    expect(g.isWrong(i), isTrue);
    expect(g.erase(), isTrue);
    expect(g.values[i], 0);
    expect(g.undo(), isTrue);
    expect(g.values[i], wrongDigit(i));
    expect(g.mistakes, 1, reason: 'undo never refunds a mistake');
  });

  test('notes toggle, and placing a digit clears it from peers', () {
    final i = firstEmpty();
    final d = g.solution[i];
    final peer = Board.peers[i].firstWhere((p) => g.values[p] == 0);
    g.toggleNotesMode();
    g.select(peer);
    expect(g.input(d), InputResult.noted);
    expect(g.notes[peer] & (1 << d), isNot(0));
    g.select(i);
    g.input(d);
    g.toggleNotesMode();
    expect(g.input(d), InputResult.placed);
    expect(g.notes[i], 0);
    expect(g.notes[peer] & (1 << d), 0);
    // Undo restores both the cell and the peer's note.
    g.undo();
    expect(g.values[i], 0);
    expect(g.notes[i] & (1 << d), isNot(0));
    expect(g.notes[peer] & (1 << d), isNot(0));
  });

  test('hint reveals selected wrong cell, first one is free', () {
    final i = firstEmpty();
    g.select(i);
    g.input(wrongDigit(i));
    expect(g.hasFreeHint, isTrue);
    expect(g.hint(), i);
    expect(g.values[i], g.solution[i]);
    expect(g.hasFreeHint, isFalse);
    // The revealed cell can't be reverted by undo.
    while (g.undo()) {}
    expect(g.values[i], g.solution[i]);
  });

  test('filling every cell wins', () {
    InputResult? last;
    for (var i = 0; i < 81; i++) {
      if (g.values[i] != 0) continue;
      g.select(i);
      last = g.input(g.solution[i]);
    }
    expect(last, InputResult.won);
    expect(g.status, GameStatus.won);
    expect(g.remaining(5), 0);
  });

  test('hint can finish the game', () {
    while (g.status == GameStatus.playing) {
      expect(g.hint(), isNotNull);
    }
    expect(g.status, GameStatus.won);
  });

  test('timer only ticks while playing and not paused', () {
    g.tick();
    expect(g.elapsed.value, 1);
    g.setPaused(true);
    g.tick();
    expect(g.elapsed.value, 1);
    g.setPaused(false);
    g.tick();
    expect(g.elapsed.value, 2);
  });

  test('paused game ignores input', () {
    final i = firstEmpty();
    g.select(i);
    g.setPaused(true);
    expect(g.input(g.solution[i]), InputResult.ignored);
  });

  test('json round trip keeps the full state', () {
    final i = firstEmpty();
    g.select(i);
    g.input(wrongDigit(i));
    g.toggleNotesMode();
    final j = g.values.indexOf(0, i + 1);
    g.select(j);
    g.input(3);
    g.hint();
    g.tick();
    final copy = GameController.fromJson(g.toJson());
    expect(copy.values, g.values);
    expect(copy.notes, g.notes);
    expect(copy.givens, g.givens);
    expect(copy.solution, g.solution);
    expect(copy.mistakes, 1);
    expect(copy.hintsUsed, 1);
    expect(copy.elapsed.value, 1);
    expect(copy.difficulty, Difficulty.medium);
    expect(copy.dailyDate, isNull);
    copy.dispose();
  });

  test('restoring a game saved at 3 mistakes starts in lost state', () {
    final json = g.toJson()..['mistakes'] = 3;
    final copy = GameController.fromJson(json);
    expect(copy.status, GameStatus.lost);
    expect(copy.canRevive, isTrue);
    copy.dispose();
  });
}
