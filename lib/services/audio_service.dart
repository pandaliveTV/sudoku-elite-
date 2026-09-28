import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'storage_service.dart';

/// Available sound effects (files in `assets/sounds/<name>.wav`).
enum Sfx { tap, place, error, hint, win, lose, coin }

/// Short sound effects and light haptics, both respecting user settings.
class AudioService {
  AudioService(this.storage);

  final StorageService storage;
  final _pool = <Sfx, AudioPlayer>{};

  Future<void> play(Sfx sfx) async {
    if (storage.muted) return;
    try {
      final player = _pool.putIfAbsent(
        sfx,
        () => AudioPlayer()..setPlayerMode(PlayerMode.lowLatency),
      );
      await player.stop();
      await player.play(AssetSource('sounds/${sfx.name}.wav'));
    } catch (_) {
      // Audio is non-critical.
    }
  }

  void light() {
    if (storage.vibration) HapticFeedback.lightImpact();
  }

  void selection() {
    if (storage.vibration) HapticFeedback.selectionClick();
  }

  void heavy() {
    if (storage.vibration) HapticFeedback.mediumImpact();
  }

  void dispose() {
    for (final p in _pool.values) {
      p.dispose();
    }
  }
}
