import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/difficulty.dart';
import '../data/strings.dart';
import '../services/storage_service.dart';
import '../widgets/common.dart';
import 'game_screen.dart';

/// The "levels" screen: pick one of the four difficulties.
class DifficultyScreen extends StatelessWidget {
  const DifficultyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('choose_difficulty'))),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: MaxWidth(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final d in Difficulty.values)
                      _DifficultyCard(difficulty: d, stats: storage.stats[d]!),
                  ],
                ),
              ),
            ),
            const BannerSlot(),
          ],
        ),
      ),
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({required this.difficulty, required this.stats});

  final Difficulty difficulty;
  final DifficultyStats stats;

  @override
  Widget build(BuildContext context) {
    final color = difficultyColor(difficulty);
    final stars = Difficulty.values.indexOf(difficulty) + 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          if (!await confirmAbandon(context) || !context.mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => GameScreen(difficulty: difficulty),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < stars; i++)
                      Icon(Icons.star_rounded, color: color, size: 20),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.difficultyName(difficulty),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(context.tr('${difficulty.key}_desc')),
                    const SizedBox(height: 6),
                    Text(
                      [
                        context.tr('wins_count', {'n': '${stats.won}'}),
                        if (stats.bestTime > 0)
                          context.tr('best', {'t': formatTime(stats.bestTime)}),
                      ].join('  •  '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.monetization_on,
                    color: Colors.amber,
                    size: 18,
                  ),
                  Text(' ${difficulty.coins}'),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
