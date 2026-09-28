import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/sudoku_engine.dart';

/// The 9x9 grid, drawn with a single CustomPainter (cheap to repaint at
/// 60fps). Always laid out left-to-right, even in Arabic.
class SudokuBoard extends StatelessWidget {
  const SudokuBoard({
    super.key,
    required this.game,
    required this.highlightSame,
    required this.onSelect,
  });

  final GameController game;
  final bool highlightSame;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = BoardColors.of(Theme.of(context).colorScheme);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, c) {
            final cell = c.maxWidth / 9;
            return GestureDetector(
              onTapDown: (d) {
                final col = (d.localPosition.dx / cell).floor().clamp(0, 8);
                final row = (d.localPosition.dy / cell).floor().clamp(0, 8);
                onSelect(row * 9 + col);
              },
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.square(c.maxWidth),
                  painter: _BoardPainter(
                    game: game,
                    colors: colors,
                    highlightSame: highlightSame,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class BoardColors {
  const BoardColors({
    required this.background,
    required this.given,
    required this.user,
    required this.wrong,
    required this.selected,
    required this.peer,
    required this.same,
    required this.thinLine,
    required this.thickLine,
    required this.note,
  });

  factory BoardColors.of(ColorScheme s) => BoardColors(
    background: s.surface,
    given: s.onSurface,
    user: s.primary,
    wrong: s.error,
    selected: s.primary.withValues(alpha: 0.32),
    peer: s.primary.withValues(alpha: 0.08),
    same: s.primary.withValues(alpha: 0.20),
    thinLine: s.outlineVariant,
    thickLine: s.onSurface.withValues(alpha: 0.75),
    note: s.onSurfaceVariant,
  );

  final Color background,
      given,
      user,
      wrong,
      selected,
      peer,
      same,
      thinLine,
      thickLine,
      note;
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.game,
    required this.colors,
    required this.highlightSame,
  }) : super(repaint: game);

  final GameController game;
  final BoardColors colors;
  final bool highlightSame;

  static final Map<String, TextPainter> _textCache = {};

  TextPainter _text(String s, Color color, double size, FontWeight w) {
    final key = '$s|${color.toARGB32()}|${size.toStringAsFixed(1)}|${w.value}';
    return _textCache.putIfAbsent(key, () {
      if (_textCache.length > 400) _textCache.clear();
      return TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(color: color, fontSize: size, fontWeight: w),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 9;
    final paint = Paint();
    canvas.drawRect(Offset.zero & size, paint..color = colors.background);

    final sel = game.selected;
    final selValue = sel == null ? 0 : game.values[sel];

    // Highlights.
    for (var i = 0; i < 81; i++) {
      Color? bg;
      if (i == sel) {
        bg = colors.selected;
      } else if (highlightSame && selValue != 0 && game.values[i] == selValue) {
        bg = colors.same;
      } else if (sel != null &&
          (Board.rowOf[i] == Board.rowOf[sel] ||
              Board.colOf[i] == Board.colOf[sel] ||
              Board.boxOf[i] == Board.boxOf[sel])) {
        bg = colors.peer;
      }
      if (game.isWrong(i) && i != sel) {
        bg = colors.wrong.withValues(alpha: 0.12);
      }
      if (bg != null) {
        canvas.drawRect(
          Rect.fromLTWH(
            Board.colOf[i] * cell,
            Board.rowOf[i] * cell,
            cell,
            cell,
          ),
          paint..color = bg,
        );
      }
    }

    // Digits and notes.
    final digitSize = cell * 0.6;
    final noteSize = cell * 0.26;
    for (var i = 0; i < 81; i++) {
      final x = Board.colOf[i] * cell;
      final y = Board.rowOf[i] * cell;
      final v = game.values[i];
      if (v != 0) {
        final color = game.isGiven(i)
            ? colors.given
            : game.isWrong(i)
            ? colors.wrong
            : colors.user;
        final tp = _text(
          '$v',
          color,
          digitSize,
          game.isGiven(i) ? FontWeight.w600 : FontWeight.w500,
        );
        tp.paint(
          canvas,
          Offset(x + (cell - tp.width) / 2, y + (cell - tp.height) / 2),
        );
        continue;
      }
      final n = game.notes[i];
      if (n == 0) continue;
      final sub = cell / 3;
      for (var d = 1; d <= 9; d++) {
        if (n & (1 << d) == 0) continue;
        final match = highlightSame && d == selValue;
        final tp = _text(
          '$d',
          match ? colors.user : colors.note,
          noteSize,
          match ? FontWeight.w900 : FontWeight.w500,
        );
        final nx = x + ((d - 1) % 3) * sub;
        final ny = y + ((d - 1) ~/ 3) * sub;
        tp.paint(
          canvas,
          Offset(nx + (sub - tp.width) / 2, ny + (sub - tp.height) / 2),
        );
      }
    }

    // Grid lines: thin first, thick box borders on top.
    paint
      ..color = colors.thinLine
      ..strokeWidth = 1;
    for (var k = 1; k < 9; k++) {
      if (k % 3 == 0) continue;
      final p = k * cell;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), paint);
      canvas.drawLine(Offset(0, p), Offset(size.width, p), paint);
    }
    paint
      ..color = colors.thickLine
      ..strokeWidth = 2;
    for (var k = 3; k < 9; k += 3) {
      final p = k * cell;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), paint);
      canvas.drawLine(Offset(0, p), Offset(size.width, p), paint);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(1),
        const Radius.circular(4),
      ),
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    paint.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.game != game ||
      old.highlightSame != highlightSame ||
      old.colors.background != colors.background;
}

/// Digit buttons 1–9 with the count still to be placed.
class NumberPad extends StatelessWidget {
  const NumberPad({super.key, required this.game, required this.onDigit});

  final GameController game;
  final ValueChanged<int> onDigit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          for (var d = 1; d <= 9; d++)
            Expanded(child: _digit(context, scheme, d, game.remaining(d))),
        ],
      ),
    );
  }

  Widget _digit(BuildContext context, ColorScheme scheme, int d, int left) {
    final done = left <= 0;
    final enabled = !done || game.notesMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: AspectRatio(
        aspectRatio: 0.72,
        child: Material(
          color: enabled
              ? scheme.primaryContainer.withValues(alpha: 0.55)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? () => onDigit(d) : null,
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    Text(
                      '$d',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? (game.notesMode
                                  ? scheme.onSurfaceVariant
                                  : scheme.primary)
                            : scheme.outline,
                      ),
                    ),
                    Text(
                      done ? '✓' : '$left',
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
