import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/daily.dart';
import '../data/difficulty.dart';
import '../data/strings.dart';
import '../services/storage_service.dart';
import '../widgets/common.dart';
import 'daily_screen.dart';
import 'difficulty_screen.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final saved = storage.loadGame();
    final todayDone = storage.dailyDone.contains(Daily.key(Daily.today()));

    String? savedLabel;
    if (saved != null) {
      final d = Difficulty.fromKey(saved['difficulty'] as String);
      final t = formatTime(saved['elapsed'] as int? ?? 0);
      savedLabel = saved['daily'] != null
          ? '${context.tr('daily')} • $t'
          : '${context.difficultyName(d)} • $t';
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  const LevelBadge(),
                  const Spacer(),
                  const CoinBadge(),
                  IconButton(
                    tooltip: context.tr('settings'),
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => _push(context, const SettingsScreen()),
                  ),
                ],
              ),
            ),
            Expanded(
              child: MaxWidth(
                width: 440,
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const SizedBox(height: 16),
                          const _Logo(),
                          const SizedBox(height: 24),
                          Column(
                            children: [
                              if (savedLabel != null) ...[
                                BigButton(
                                  context.tr('continue'),
                                  subtitle: savedLabel,
                                  icon: Icons.play_arrow_rounded,
                                  onPressed: () => _push(
                                    context,
                                    const GameScreen(resume: true),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              BigButton(
                                context.tr('play'),
                                icon: Icons.add_rounded,
                                primary: savedLabel == null,
                                onPressed: () =>
                                    _push(context, const DifficultyScreen()),
                              ),
                              const SizedBox(height: 12),
                              BigButton(
                                context.tr('daily'),
                                icon: todayDone
                                    ? Icons.emoji_events
                                    : Icons.calendar_month_rounded,
                                primary: false,
                                onPressed: () =>
                                    _push(context, const DailyScreen()),
                              ),
                              const SizedBox(height: 12),
                              BigButton(
                                context.tr('stats'),
                                icon: Icons.bar_chart_rounded,
                                primary: false,
                                onPressed: () =>
                                    _push(context, const StatsScreen()),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const BannerSlot(),
          ],
        ),
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    const digits = [5, 3, 0, 0, 7, 0, 9, 0, 1];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: 108,
          height: 108,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: brandGradient,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: GridView.count(
            crossAxisCount: 3,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final d in digits)
                Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: d == 0 ? 0.25 : 0.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: d == 0
                      ? null
                      : Text(
                          '$d',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: Color(0xFF3D5AFE),
                          ),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'SUDOKU',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            color: scheme.onSurface,
          ),
        ),
        Text(
          'ELITE',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 10,
            color: scheme.primary,
          ),
        ),
      ],
    );
  }
}
