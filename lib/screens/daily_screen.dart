import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/daily.dart';
import '../data/strings.dart';
import '../services/storage_service.dart';
import '../widgets/common.dart';
import 'game_screen.dart';

/// Daily challenge calendar with monthly trophies.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = Daily.today();
    _month = DateTime(_selected.year, _selected.month);
  }

  bool get _canGoBack =>
      _month.isAfter(DateTime(Daily.firstDay.year, Daily.firstDay.month));

  bool get _canGoForward {
    final t = Daily.today();
    return _month.isBefore(DateTime(t.year, t.month));
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      final today = Daily.today();
      final last = DateTime(
        _month.year,
        _month.month,
        Daily.daysInMonth(_month.year, _month.month),
      );
      _selected = last.isAfter(today) ? today : last;
    });
  }

  Future<void> _play() async {
    final storage = context.read<StorageService>();
    final key = Daily.key(_selected);
    final saved = storage.loadGame();
    final Widget screen;
    if (saved != null && saved['daily'] == key) {
      screen = const GameScreen(resume: true);
    } else {
      if (!await confirmAbandon(context) || !mounted) return;
      screen = GameScreen(daily: _selected);
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final loc = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final days = Daily.daysInMonth(_month.year, _month.month);
    final done = storage.dailyDoneInMonth(_month.year, _month.month);
    final trophy = Daily.trophy(done, days);
    final selectedDone = storage.dailyDone.contains(Daily.key(_selected));
    final difficulty = Daily.difficulty(_selected);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('daily_title'))),
      body: SafeArea(
        top: false,
        child: MaxWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  _TrophyIcon(trophy: trophy, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.formatMonthYear(_month),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          context.tr('days_done', {'n': '$done', 'm': '$days'}),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _canGoBack ? () => _shiftMonth(-1) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _canGoForward ? () => _shiftMonth(1) : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: done / days,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 16),
              _Calendar(
                month: _month,
                selected: _selected,
                done: storage.dailyDone,
                onSelect: (d) => setState(() => _selected = d),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.formatFullDate(_selected),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.difficultyName(difficulty),
                              style: TextStyle(
                                color: difficultyColor(difficulty),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selectedDone)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: Icon(
                            Icons.check_circle,
                            color: scheme.primary,
                          ),
                        ),
                      FilledButton(
                        onPressed: _play,
                        child: Text(context.tr('play_day')),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('trophies'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('trophy_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _TrophyShelf(storage: storage),
            ],
          ),
        ),
      ),
    );
  }
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.selected,
    required this.done,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final Set<String> done;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final today = Daily.today();
    final days = Daily.daysInMonth(month.year, month.month);
    // Offset of the 1st relative to the locale's first day of week.
    final firstWeekday = DateTime(month.year, month.month).weekday % 7; // Sun=0
    final lead = (firstWeekday - loc.firstDayOfWeekIndex + 7) % 7;
    final headers = [
      for (var k = 0; k < 7; k++)
        loc.narrowWeekdays[(loc.firstDayOfWeekIndex + k) % 7],
    ];

    return Column(
      children: [
        Row(
          children: [
            for (final h in headers)
              Expanded(
                child: Center(
                  child: Text(
                    h,
                    style: TextStyle(
                      color: scheme.outline,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (var k = 0; k < lead; k++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              _dayCell(
                context,
                scheme,
                DateTime(month.year, month.month, d),
                today,
              ),
          ],
        ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    ColorScheme scheme,
    DateTime day,
    DateTime today,
  ) {
    final future = day.isAfter(today);
    final isDone = done.contains(Daily.key(day));
    final isSelected = day == selected;
    final isToday = day == today;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: future ? null : () => onSelect(day),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? scheme.primary
              : isDone
              ? scheme.primaryContainer
              : null,
          border: isToday && !isSelected
              ? Border.all(color: scheme.primary, width: 2)
              : null,
        ),
        alignment: Alignment.center,
        child: isDone && !isSelected
            ? Icon(Icons.star_rounded, color: scheme.primary, size: 22)
            : Text(
                '${day.day}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? scheme.onPrimary
                      : future
                      ? scheme.outlineVariant
                      : scheme.onSurface,
                ),
              ),
      ),
    );
  }
}

class _TrophyShelf extends StatelessWidget {
  const _TrophyShelf({required this.storage});

  final StorageService storage;

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final today = Daily.today();
    final months = <DateTime>[];
    for (
      var m = DateTime(today.year, today.month);
      !m.isBefore(DateTime(Daily.firstDay.year, Daily.firstDay.month));
      m = DateTime(m.year, m.month - 1)
    ) {
      months.add(m);
    }
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final m = months[i];
          final days = Daily.daysInMonth(m.year, m.month);
          final done = storage.dailyDoneInMonth(m.year, m.month);
          return Container(
            width: 96,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TrophyIcon(trophy: Daily.trophy(done, days), size: 40),
                const SizedBox(height: 4),
                Text(
                  loc.formatMonthYear(m),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  '$done/$days',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrophyIcon extends StatelessWidget {
  const _TrophyIcon({required this.trophy, required this.size});

  final Trophy trophy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = switch (trophy) {
      Trophy.gold => const Color(0xFFFFC107),
      Trophy.silver => const Color(0xFFB0BEC5),
      Trophy.bronze => const Color(0xFFCD7F32),
      Trophy.none => Theme.of(context).colorScheme.outlineVariant,
    };
    return Icon(Icons.emoji_events, color: color, size: size);
  }
}
