import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/difficulty.dart';
import '../data/strings.dart';
import '../services/storage_service.dart';
import '../widgets/common.dart';

/// Statistics per difficulty: best time, win rate, streaks.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  Future<void> _confirmReset(BuildContext context) async {
    final storage = context.read<StorageService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.tr('reset_stats')),
        content: Text(c.tr('reset_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(c.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(c.tr('reset')),
          ),
        ],
      ),
    );
    if (ok == true) storage.resetStats();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    return DefaultTabController(
      length: Difficulty.values.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('stats')),
          actions: [
            IconButton(
              tooltip: context.tr('reset_stats'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmReset(context),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: [
              Tab(text: context.tr('overview')),
              for (final d in Difficulty.values)
                Tab(text: context.difficultyName(d)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Overview(storage: storage),
            for (final d in Difficulty.values)
              _DifficultyStatsView(difficulty: d, stats: storage.stats[d]!),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.storage});

  final StorageService storage;

  @override
  Widget build(BuildContext context) {
    final played = storage.stats.values.fold(0, (a, s) => a + s.played);
    final won = storage.stats.values.fold(0, (a, s) => a + s.won);
    final best = storage.bestTimeOverall;
    return MaxWidth(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Tile(
            icon: Icons.military_tech,
            label: context.tr('level', {'n': '${storage.level}'}),
            value: '${storage.xp} XP',
          ),
          _Tile(
            icon: Icons.monetization_on,
            label: context.tr('coins'),
            value: '${storage.coins}',
          ),
          _Tile(
            icon: Icons.grid_on,
            label: context.tr('games_played'),
            value: '$played',
          ),
          _Tile(
            icon: Icons.emoji_events_outlined,
            label: context.tr('games_won'),
            value: '$won',
          ),
          _Tile(
            icon: Icons.percent,
            label: context.tr('win_rate'),
            value: played == 0 ? '—' : '${(won * 100 / played).round()}%',
          ),
          _Tile(
            icon: Icons.timer_outlined,
            label: context.tr('best_time'),
            value: best == 0 ? '—' : formatTime(best),
          ),
          _Tile(
            icon: Icons.calendar_month,
            label: context.tr('daily'),
            value: '${storage.dailyDone.length}',
          ),
        ],
      ),
    );
  }
}

class _DifficultyStatsView extends StatelessWidget {
  const _DifficultyStatsView({required this.difficulty, required this.stats});

  final Difficulty difficulty;
  final DifficultyStats stats;

  @override
  Widget build(BuildContext context) {
    final color = difficultyColor(difficulty);
    return MaxWidth(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: SizedBox(
              width: 140,
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: stats.winRate,
                    strokeWidth: 12,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(stats.winRate * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(context.tr('win_rate')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _Tile(
            icon: Icons.grid_on,
            label: context.tr('games_played'),
            value: '${stats.played}',
          ),
          _Tile(
            icon: Icons.emoji_events_outlined,
            label: context.tr('games_won'),
            value: '${stats.won}',
          ),
          _Tile(
            icon: Icons.timer_outlined,
            label: context.tr('best_time'),
            value: stats.bestTime == 0 ? '—' : formatTime(stats.bestTime),
          ),
          _Tile(
            icon: Icons.av_timer,
            label: context.tr('avg_time'),
            value: stats.averageTime == 0 ? '—' : formatTime(stats.averageTime),
          ),
          _Tile(
            icon: Icons.local_fire_department_outlined,
            label: context.tr('current_streak'),
            value: '${stats.streak}',
          ),
          _Tile(
            icon: Icons.whatshot,
            label: context.tr('best_streak'),
            value: '${stats.bestStreak}',
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
