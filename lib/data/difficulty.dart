/// The four puzzle difficulties and the rules the generator uses for each.
enum Difficulty {
  easy(
    key: 'easy',
    targetClues: 38,
    coins: 10,
    xp: 20,
    symmetric: true,
    technique: SolveTechnique.nakedSingles,
  ),
  medium(
    key: 'medium',
    targetClues: 32,
    coins: 20,
    xp: 35,
    symmetric: true,
    technique: SolveTechnique.singles,
  ),
  hard(
    key: 'hard',
    targetClues: 27,
    coins: 35,
    xp: 50,
    symmetric: true,
    technique: SolveTechnique.any,
  ),
  expert(
    key: 'expert',
    targetClues: 22,
    coins: 50,
    xp: 80,
    symmetric: false,
    technique: SolveTechnique.beyondSingles,
  );

  const Difficulty({
    required this.key,
    required this.targetClues,
    required this.coins,
    required this.xp,
    required this.symmetric,
    required this.technique,
  });

  /// Stable id used in storage and in translation keys.
  final String key;

  /// The generator stops removing digits once it reaches this many clues
  /// (it may stop earlier when no further digit can be removed while keeping
  /// the solution unique / within [technique]).
  final int targetClues;

  /// Coins awarded for a win.
  final int coins;

  /// Experience points awarded for a win (drives the player level).
  final int xp;

  /// Remove clues in 180° rotational pairs (classic look).
  final bool symmetric;

  /// Which human solving techniques the puzzle may require.
  final SolveTechnique technique;

  static Difficulty fromKey(String key) =>
      values.firstWhere((d) => d.key == key, orElse: () => Difficulty.easy);
}

enum SolveTechnique {
  /// Solvable using only naked singles (cells with a single candidate).
  nakedSingles,

  /// Solvable using naked + hidden singles.
  singles,

  /// Any puzzle with a unique solution.
  any,

  /// Unique solution that can NOT be finished with singles alone.
  beyondSingles,
}
