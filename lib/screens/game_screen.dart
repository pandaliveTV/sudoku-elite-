import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/daily.dart';
import '../data/difficulty.dart';
import '../data/strings.dart';
import '../game/game_controller.dart';
import '../game/sudoku_engine.dart';
import '../services/ad_service.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import '../widgets/common.dart';
import '../widgets/end_dialogs.dart';
import '../widgets/sudoku_board.dart';
import 'daily_screen.dart';

/// Gameplay screen. No banner ads here by design.
///
/// Exactly one of [difficulty] (new classic game), [daily] (daily challenge)
/// or [resume] (continue the autosaved game) should be set.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.difficulty,
    this.daily,
    this.resume = false,
  });

  final Difficulty? difficulty;
  final DateTime? daily;
  final bool resume;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final StorageService _storage;
  late final AudioService _audio;
  late final AdService _ads;
  GameController? _game;
  Timer? _timer;

  /// True while a rewarded ad is on screen, so we don't auto-pause for it.
  bool _inAd = false;

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    _audio = context.read<AudioService>();
    _ads = context.read<AdService>();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    GameController? game;
    if (widget.resume) {
      final json = _storage.loadGame();
      if (json != null) {
        try {
          game = GameController.fromJson(json);
        } catch (_) {
          _storage.clearSavedGame();
        }
      }
    }
    if (game == null) {
      final daily = widget.daily;
      final d = daily != null
          ? Daily.difficulty(daily)
          : widget.difficulty ?? Difficulty.easy;
      // Generate off the UI isolate to keep 60fps.
      final flat = await compute(generatePuzzleIsolate, (
        d.key,
        daily != null ? Daily.seed(daily) : null,
      ));
      game = GameController(
        givens: flat.sublist(0, 81),
        solution: flat.sublist(81),
        difficulty: d,
        dailyDate: daily != null ? Daily.key(daily) : null,
      );
      if (!game.isDaily) _storage.recordStarted(d);
    }
    if (!mounted) {
      _storage.saveGame(game.toJson());
      game.dispose();
      return;
    }
    setState(() => _game = game);
    _save();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final g = _game;
      if (g == null) return;
      g.tick();
      if (g.elapsed.value % 10 == 0) _save();
    });
    if (game.status == GameStatus.lost) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onLost());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final g = _game;
    if (g == null || g.status != GameStatus.playing) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_inAd) g.setPaused(true);
      _save();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _save();
    _game?.dispose();
    super.dispose();
  }

  void _save() {
    final g = _game;
    if (g != null && g.status == GameStatus.playing) {
      _storage.saveGame(g.toJson());
    }
  }

  // ------------------------------------------------------------ input

  void _onSelect(int i) {
    final g = _game!;
    if (g.paused) return;
    if (g.selected != i) _audio.selection();
    g.select(i);
  }

  void _onDigit(int d) {
    final g = _game!;
    switch (g.input(d)) {
      case InputResult.ignored:
        return;
      case InputResult.noted:
        _audio.play(Sfx.tap);
        _audio.light();
      case InputResult.placed:
        _audio.play(Sfx.place);
        _audio.light();
      case InputResult.mistake:
        _audio.play(Sfx.error);
        _audio.heavy();
      case InputResult.lost:
        _audio.play(Sfx.lose);
        _audio.heavy();
        _onLost();
        return;
      case InputResult.won:
        _onWon();
        return;
    }
    _save();
  }

  void _onErase() {
    if (_game!.erase()) {
      _audio.play(Sfx.tap);
      _audio.light();
      _save();
    }
  }

  void _onUndo() {
    if (_game!.undo()) {
      _audio.play(Sfx.tap);
      _audio.light();
      _save();
    }
  }

  Future<void> _onHint() async {
    final g = _game!;
    if (g.status != GameStatus.playing || g.paused) return;
    if (!g.hasFreeHint) {
      final watch = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.lightbulb, color: Colors.amber, size: 40),
          title: Text(c.tr('hint_title')),
          content: Text(c.tr('hint_desc')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(c.tr('cancel')),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(c, true),
              icon: const Icon(Icons.ondemand_video),
              label: Text(c.tr('watch_ad')),
            ),
          ],
        ),
      );
      if (watch != true || !mounted) return;
      _inAd = true;
      final earned = await watchRewarded(context);
      _inAd = false;
      if (!earned || !mounted) return;
    }
    if (g.hint() == null) return;
    _audio.play(Sfx.hint);
    _audio.light();
    if (g.status == GameStatus.won) {
      _onWon();
    } else {
      _save();
    }
  }

  // ------------------------------------------------------------ game end

  Future<void> _onWon() async {
    final g = _game!;
    _audio.play(Sfx.win);
    _audio.heavy();
    _storage.clearSavedGame();
    final seconds = g.elapsed.value;
    var coins = g.difficulty.coins;
    var record = false;
    if (g.isDaily) {
      coins += Daily.bonusCoins;
      _storage.markDailyDone(g.dailyDate!);
    } else {
      record = _storage.recordWin(g.difficulty, seconds);
    }
    _storage
      ..addCoins(coins)
      ..addXp(g.difficulty.xp);

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _inAd = true;
    final action = await showDialog<EndAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WinDialog(
        seconds: seconds,
        coins: coins,
        record: record,
        daily: g.isDaily,
      ),
    );
    _inAd = false;
    if (!mounted) return;
    _finishRound(action ?? EndAction.home);
  }

  Future<void> _onLost() async {
    final g = _game!;
    _inAd = true;
    final action = await showDialog<EndAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LostDialog(canRevive: g.canRevive),
    );
    _inAd = false;
    if (!mounted) return;
    if (action == EndAction.revive && g.revive()) {
      _save();
      return;
    }
    if (!g.isDaily) _storage.recordLoss(g.difficulty);
    _storage.clearSavedGame();
    _finishRound(action ?? EndAction.home);
  }

  void _finishRound(EndAction action) {
    final g = _game!;
    _ads.onRoundFinished();
    if (action != EndAction.newGame) {
      Navigator.pop(context);
      return;
    }
    final next = g.isDaily
        ? const DailyScreen()
        : GameScreen(difficulty: g.difficulty);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => next));
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final g = _game;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          g == null
              ? ''
              : g.isDaily
              ? '${context.tr('daily')} • ${context.difficultyName(g.difficulty)}'
              : context.difficultyName(g.difficulty),
        ),
      ),
      body: SafeArea(
        top: false,
        child: g == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(context.tr('generating')),
                  ],
                ),
              )
            : ListenableBuilder(
                listenable: g,
                builder: (context, _) => _buildGame(context, g),
              ),
      ),
    );
  }

  Widget _buildGame(BuildContext context, GameController g) {
    final highlight = context.select<StorageService, bool>(
      (s) => s.highlightSame,
    );
    return LayoutBuilder(
      builder: (context, c) {
        // Leave room for the header, tools and number pad.
        final boardSize = [
          c.maxWidth - 16,
          c.maxHeight - 250,
          600.0,
        ].reduce((a, b) => a < b ? a : b);
        return Center(
          child: SizedBox(
            width: boardSize,
            height: c.maxHeight,
            child: Column(
              children: [
                const SizedBox(height: 4),
                _Header(game: g, onPause: () => g.setPaused(!g.paused)),
                const SizedBox(height: 4),
                Stack(
                  children: [
                    SudokuBoard(
                      game: g,
                      highlightSame: highlight,
                      onSelect: _onSelect,
                    ),
                    if (g.paused)
                      Positioned.fill(
                        child: _PausedOverlay(
                          onResume: () => g.setPaused(false),
                        ),
                      ),
                  ],
                ),
                const Spacer(flex: 2),
                _Tools(
                  game: g,
                  onUndo: _onUndo,
                  onErase: _onErase,
                  onNotes: g.toggleNotesMode,
                  onHint: _onHint,
                ),
                const SizedBox(height: 12),
                NumberPad(game: g, onDigit: _onDigit),
                const Spacer(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.game, required this.onPause});

  final GameController game;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: scheme.onSurfaceVariant, fontSize: 15);
    return Row(
      children: [
        Text('${context.tr('mistakes')}: ', style: style),
        Text(
          '${game.mistakes}/${GameController.maxMistakes}',
          style: style.copyWith(
            fontWeight: FontWeight.w700,
            color: game.mistakes > 0 ? scheme.error : null,
          ),
        ),
        const Spacer(),
        ValueListenableBuilder<int>(
          valueListenable: game.elapsed,
          builder: (_, s, _) => Text(
            formatTime(s),
            style: style.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            game.paused
                ? Icons.play_circle_outline
                : Icons.pause_circle_outline,
          ),
          onPressed: game.status == GameStatus.playing ? onPause : null,
        ),
      ],
    );
  }
}

class _PausedOverlay extends StatelessWidget {
  const _PausedOverlay({required this.onResume});

  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('paused'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(context.tr('resume')),
          ),
        ],
      ),
    );
  }
}

class _Tools extends StatelessWidget {
  const _Tools({
    required this.game,
    required this.onUndo,
    required this.onErase,
    required this.onNotes,
    required this.onHint,
  });

  final GameController game;
  final VoidCallback onUndo, onErase, onNotes, onHint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _ToolButton(
          icon: Icons.undo_rounded,
          label: context.tr('undo'),
          onTap: game.canUndo ? onUndo : null,
        ),
        _ToolButton(
          icon: Icons.auto_fix_normal_outlined,
          label: context.tr('erase'),
          onTap: onErase,
        ),
        _ToolButton(
          icon: Icons.edit_outlined,
          label: context.tr('notes'),
          onTap: onNotes,
          active: game.notesMode,
          badge: game.notesMode ? context.tr('on') : context.tr('off'),
          badgeColor: game.notesMode ? scheme.primary : scheme.outline,
        ),
        _ToolButton(
          icon: Icons.lightbulb_outline,
          label: context.tr('hint'),
          onTap: onHint,
          badge: game.hasFreeHint ? context.tr('free') : null,
          badgeIcon: game.hasFreeHint ? null : Icons.ondemand_video,
          badgeColor: game.hasFreeHint ? Colors.green : Colors.amber.shade800,
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.badge,
    this.badgeIcon,
    this.badgeColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final String? badge;
  final IconData? badgeIcon;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = onTap == null
        ? scheme.outline
        : active
        ? scheme.primary
        : scheme.onSurfaceVariant;
    Widget iconWidget = Icon(icon, size: 28, color: color);
    if (badge != null || badgeIcon != null) {
      iconWidget = Badge(
        backgroundColor: badgeColor,
        offset: const Offset(14, -6),
        label: badgeIcon != null
            ? Icon(badgeIcon, size: 10, color: Colors.white)
            : Text(badge!, style: const TextStyle(fontSize: 9)),
        child: iconWidget,
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
