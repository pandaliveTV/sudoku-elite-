import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/difficulty.dart';
import '../data/strings.dart';
import '../services/ad_service.dart';
import '../services/storage_service.dart';

/// TODO(EliteP): replace with the published EliteP privacy policy URL.
const privacyPolicyUrl = 'https://elitep.com/privacy';

const appVersion = '1.0.0';

const brandGradient = LinearGradient(
  colors: [Color(0xFF3D5AFE), Color(0xFF7C4DFF)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

Future<void> openPrivacyPolicy(BuildContext context) {
  context.read<AdService>().skipNextAppOpen();
  return launchUrl(
    Uri.parse(privacyPolicyUrl),
    mode: LaunchMode.externalApplication,
  );
}

/// Centers content and caps its width so tablets look good too.
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 520});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
}

class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final coins = context.select<StorageService, int>((s) => s.coins);
    return _Pill(
      children: [
        const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
        const SizedBox(width: 6),
        Text('$coins', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<StorageService>();
    final scheme = Theme.of(context).colorScheme;
    return _Pill(
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            value: s.levelProgress,
            strokeWidth: 3,
            backgroundColor: scheme.outlineVariant,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          context.tr('level', {'n': '${s.level}'}),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

class BigButton extends StatelessWidget {
  const BigButton(
    this.label, {
    super.key,
    required this.icon,
    this.onPressed,
    this.primary = true,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 58)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, overflow: TextOverflow.ellipsis),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return primary
        ? FilledButton(style: style, onPressed: onPressed, child: child)
        : FilledButton.tonal(style: style, onPressed: onPressed, child: child);
  }
}

/// Banner shown only on menu screens (Home / Difficulty), never in-game.
/// Waits for consent + SDK init and for the first-launch grace period.
class BannerSlot extends StatefulWidget {
  const BannerSlot({super.key});

  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  late final AdService _ads;
  BannerAd? _ad;
  bool _loaded = false;
  Timer? _graceTimer;

  @override
  void initState() {
    super.initState();
    _ads = context.read<AdService>();
    _ads.ready.addListener(_tryLoad);
    _tryLoad();
  }

  void _tryLoad() {
    if (!mounted || _ad != null || !_ads.ready.value) return;
    final grace = _ads.graceRemaining;
    if (grace > Duration.zero) {
      _graceTimer ??= Timer(grace + const Duration(milliseconds: 300), () {
        _graceTimer = null;
        _tryLoad();
      });
      return;
    }
    _ad = _ads.createBanner(() {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _ads.ready.removeListener(_tryLoad);
    _graceTimer?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final removed = context.select<StorageService, bool>((s) => s.adsRemoved);
    final ad = _ad;
    if (removed || !_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}

/// Shows a rewarded ad; tells the player when none is available.
/// Returns true only when the reward was earned.
Future<bool> watchRewarded(BuildContext context) async {
  final ads = context.read<AdService>();
  final messenger = ScaffoldMessenger.of(context);
  final noAd = context.tr('no_ad');
  if (!ads.canShowRewarded) {
    messenger.showSnackBar(SnackBar(content: Text(noAd)));
    ads.showRewarded(); // triggers a reload
    return false;
  }
  return ads.showRewarded();
}

/// Asks before replacing a saved game. Returns true when it is OK to start.
/// An abandoned classic game counts as a loss for the win streak.
Future<bool> confirmAbandon(BuildContext context) async {
  final storage = context.read<StorageService>();
  final saved = storage.loadGame();
  if (saved == null) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(c.tr('abandon_title')),
      content: Text(c.tr('abandon_desc')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(c.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(c.tr('start')),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  if (saved['daily'] == null) {
    storage.recordLoss(Difficulty.fromKey(saved['difficulty'] as String));
  }
  storage.clearSavedGame();
  return true;
}

/// Color used for a difficulty across the app.
Color difficultyColor(Difficulty d) => switch (d) {
  Difficulty.easy => const Color(0xFF2E9E5B),
  Difficulty.medium => const Color(0xFF3D7BFE),
  Difficulty.hard => const Color(0xFFF08C00),
  Difficulty.expert => const Color(0xFFD32F4F),
};
