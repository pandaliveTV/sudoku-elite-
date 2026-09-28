import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/strings.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';
import 'common.dart';

enum EndAction { home, newGame, revive }

/// Win dialog with an optional (player-chosen) rewarded "x2 coins".
class WinDialog extends StatefulWidget {
  const WinDialog({
    super.key,
    required this.seconds,
    required this.coins,
    required this.record,
    required this.daily,
  });

  final int seconds;
  final int coins;
  final bool record;
  final bool daily;

  @override
  State<WinDialog> createState() => _WinDialogState();
}

class _WinDialogState extends State<WinDialog> {
  bool _doubled = false;
  bool _busy = false;

  Future<void> _double() async {
    setState(() => _busy = true);
    final earned = await watchRewarded(context);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!earned) return;
    context.read<StorageService>().addCoins(widget.coins);
    context.read<AudioService>().play(Sfx.coin);
    setState(() => _doubled = true);
  }

  @override
  Widget build(BuildContext context) {
    final coins = _doubled ? widget.coins * 2 : widget.coins;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.emoji_events, color: Colors.amber, size: 56),
        title: Text(
          widget.daily ? context.tr('daily_done_msg') : context.tr('you_won'),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${context.tr('win_time')}  ${formatTime(widget.seconds)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (widget.record) ...[
              const SizedBox(height: 6),
              Text(
                context.tr('new_record'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.monetization_on, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  context.tr('win_coins', {'n': '$coins'}),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!_doubled)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _double,
                icon: const Icon(Icons.ondemand_video),
                label: Text(context.tr('double_coins')),
              )
            else
              Text(context.tr('coins_doubled')),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, EndAction.home),
            child: Text(context.tr('home')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, EndAction.newGame),
            child: Text(
              widget.daily ? context.tr('daily') : context.tr('new_game'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lost dialog: "second chance" via a player-chosen rewarded ad.
class LostDialog extends StatefulWidget {
  const LostDialog({super.key, required this.canRevive});

  final bool canRevive;

  @override
  State<LostDialog> createState() => _LostDialogState();
}

class _LostDialogState extends State<LostDialog> {
  bool _busy = false;

  Future<void> _revive() async {
    setState(() => _busy = true);
    final earned = await watchRewarded(context);
    if (!mounted) return;
    setState(() => _busy = false);
    if (earned) Navigator.pop(context, EndAction.revive);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(
          Icons.heart_broken,
          color: Theme.of(context).colorScheme.error,
          size: 52,
        ),
        title: Text(context.tr('game_over'), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('lost_desc'), textAlign: TextAlign.center),
            if (widget.canRevive) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _revive,
                icon: const Icon(Icons.ondemand_video),
                label: Text(context.tr('second_chance')),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, EndAction.home),
            child: Text(context.tr('home')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, EndAction.newGame),
            child: Text(context.tr('new_game')),
          ),
        ],
      ),
    );
  }
}
