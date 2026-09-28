import 'package:flutter/foundation.dart';

import '../data/difficulty.dart';
import 'sudoku_engine.dart';

enum GameStatus { playing, won, lost }

/// What happened after a digit was entered — the UI maps it to sound/haptics.
enum InputResult { ignored, noted, placed, mistake, lost, won }

/// One cell's state before a move, used to undo it.
typedef _CellSnapshot = ({int index, int value, int notes});

/// All game rules for a single Sudoku round. Pure Dart (no Flutter widgets)
/// so it is fully unit-testable and serialisable for autosave.
class GameController extends ChangeNotifier {
  static const maxMistakes = 3;
  static const freeHints = 1;

  GameController({
    required this.givens,
    required this.solution,
    required this.difficulty,
    this.dailyDate,
  }) : values = List.of(givens),
       notes = List.filled(81, 0),
       elapsed = ValueNotifier(0);

  factory GameController.fromPuzzle(Puzzle p, {String? dailyDate}) =>
      GameController(
        givens: p.givens,
        solution: p.solution,
        difficulty: p.difficulty,
        dailyDate: dailyDate,
      );

  final List<int> givens;
  final List<int> solution;
  final Difficulty difficulty;

  /// `yyyy-mm-dd` when this is a daily challenge, otherwise null.
  final String? dailyDate;

  final List<int> values;

  /// Pencil marks per cell as a bitmask (bit d set = note d).
  final List<int> notes;

  /// Seconds played. Separate notifier so the timer does not rebuild the board.
  final ValueNotifier<int> elapsed;

  final List<List<_CellSnapshot>> _undo = [];

  int? selected;
  bool notesMode = false;
  int mistakes = 0;
  int hintsUsed = 0;
  bool secondChanceUsed = false;
  bool paused = false;
  GameStatus status = GameStatus.playing;

  bool get isDaily => dailyDate != null;
  bool get canUndo => _undo.isNotEmpty && status == GameStatus.playing;
  bool get hasFreeHint => hintsUsed < freeHints;
  bool get canRevive => status == GameStatus.lost && !secondChanceUsed;

  bool isGiven(int i) => givens[i] != 0;
  bool isWrong(int i) => values[i] != 0 && values[i] != solution[i];

  /// How many more times [digit] must be placed correctly.
  int remaining(int digit) {
    var placed = 0;
    for (var i = 0; i < 81; i++) {
      if (values[i] == digit && solution[i] == digit) placed++;
    }
    return 9 - placed;
  }

  int get filledCorrect {
    var n = 0;
    for (var i = 0; i < 81; i++) {
      if (values[i] != 0 && values[i] == solution[i]) n++;
    }
    return n;
  }

  // ---------------------------------------------------------------- actions

  void select(int index) {
    if (selected == index) return;
    selected = index;
    notifyListeners();
  }

  void toggleNotesMode() {
    notesMode = !notesMode;
    notifyListeners();
  }

  void setPaused(bool value) {
    if (paused == value) return;
    paused = value;
    notifyListeners();
  }

  /// Called once per second by the screen's timer.
  void tick() {
    if (status == GameStatus.playing && !paused) elapsed.value++;
  }

  InputResult input(int digit) {
    final i = selected;
    if (i == null || status != GameStatus.playing || paused) {
      return InputResult.ignored;
    }
    if (isGiven(i)) return InputResult.ignored;
    // Correct digits are locked in place.
    if (values[i] != 0 && !isWrong(i)) return InputResult.ignored;

    if (notesMode) {
      if (values[i] != 0) return InputResult.ignored;
      _record([i]);
      notes[i] ^= 1 << digit;
      notifyListeners();
      return InputResult.noted;
    }

    if (values[i] == digit) return InputResult.ignored;

    if (digit != solution[i]) {
      _record([i]);
      values[i] = digit;
      notes[i] = 0;
      mistakes++;
      if (mistakes >= maxMistakes) status = GameStatus.lost;
      notifyListeners();
      return status == GameStatus.lost ? InputResult.lost : InputResult.mistake;
    }

    _record([i, ...Board.peers[i].where((p) => notes[p] & (1 << digit) != 0)]);
    _placeCorrect(i);
    notifyListeners();
    return status == GameStatus.won ? InputResult.won : InputResult.placed;
  }

  /// Clears a wrong digit or the notes of the selected cell.
  bool erase() {
    final i = selected;
    if (i == null || status != GameStatus.playing || paused || isGiven(i)) {
      return false;
    }
    if (values[i] != 0 && !isWrong(i)) return false;
    if (values[i] == 0 && notes[i] == 0) return false;
    _record([i]);
    values[i] = 0;
    notes[i] = 0;
    notifyListeners();
    return true;
  }

  bool undo() {
    if (!canUndo || paused) return false;
    for (final s in _undo.removeLast()) {
      values[s.index] = s.value;
      notes[s.index] = s.notes;
    }
    notifyListeners();
    return true;
  }

  /// Reveals one cell: the selected one if it is empty/wrong, otherwise the
  /// first empty/wrong cell. Returns the revealed index, or null.
  int? hint() {
    if (status != GameStatus.playing || paused) return null;
    int? target;
    final s = selected;
    if (s != null && values[s] != solution[s]) {
      target = s;
    } else {
      for (var i = 0; i < 81; i++) {
        if (values[i] != solution[i]) {
          target = i;
          break;
        }
      }
    }
    if (target == null) return null;
    // A revealed cell must never be reverted by undo.
    for (final move in _undo) {
      move.removeWhere((c) => c.index == target);
    }
    _undo.removeWhere((m) => m.isEmpty);
    hintsUsed++;
    selected = target;
    _placeCorrect(target);
    notifyListeners();
    return target;
  }

  /// "Second chance" after losing: allows one more mistake.
  bool revive() {
    if (!canRevive) return false;
    secondChanceUsed = true;
    mistakes = maxMistakes - 1;
    status = GameStatus.playing;
    notifyListeners();
    return true;
  }

  void _placeCorrect(int i) {
    final d = solution[i];
    values[i] = d;
    notes[i] = 0;
    for (final p in Board.peers[i]) {
      notes[p] &= ~(1 << d);
    }
    if (_isSolved()) status = GameStatus.won;
  }

  bool _isSolved() {
    for (var i = 0; i < 81; i++) {
      if (values[i] != solution[i]) return false;
    }
    return true;
  }

  void _record(Iterable<int> cells) {
    _undo.add([
      for (final i in cells) (index: i, value: values[i], notes: notes[i]),
    ]);
    if (_undo.length > 200) _undo.removeAt(0);
  }

  @override
  void dispose() {
    elapsed.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ persistence

  Map<String, dynamic> toJson() => {
    'v': 1,
    'givens': givens,
    'solution': solution,
    'values': values,
    'notes': notes,
    'difficulty': difficulty.key,
    'daily': dailyDate,
    'mistakes': mistakes,
    'hints': hintsUsed,
    'revived': secondChanceUsed,
    'elapsed': elapsed.value,
    'selected': selected,
  };

  static GameController fromJson(Map<String, dynamic> j) {
    List<int> ints(String k) => (j[k] as List).cast<int>();
    final g = GameController(
      givens: ints('givens'),
      solution: ints('solution'),
      difficulty: Difficulty.fromKey(j['difficulty'] as String),
      dailyDate: j['daily'] as String?,
    );
    final values = ints('values');
    final notes = ints('notes');
    for (var i = 0; i < 81; i++) {
      g.values[i] = values[i];
      g.notes[i] = notes[i];
    }
    g.mistakes = j['mistakes'] as int? ?? 0;
    g.hintsUsed = j['hints'] as int? ?? 0;
    g.secondChanceUsed = j['revived'] as bool? ?? false;
    g.elapsed.value = j['elapsed'] as int? ?? 0;
    g.selected = j['selected'] as int?;
    if (g.mistakes >= maxMistakes) g.status = GameStatus.lost;
    return g;
  }
}
