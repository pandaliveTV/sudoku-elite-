import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'storage_service.dart';

/// ===================== AdMob unit IDs =====================
/// These are Google's official TEST ids — safe to use during development.
/// Before publishing, replace them with the EliteP ids from your AdMob
/// console, and set the EliteP App ID in
/// android/app/src/main/AndroidManifest.xml
/// (meta-data `com.google.android.gms.ads.APPLICATION_ID`).
class AdIds {
  static const banner = 'ca-app-pub-3940256099942544/6300978111';
  static const interstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const rewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const appOpen = 'ca-app-pub-3940256099942544/9257395921';
}

/// Single place for all ad logic and frequency rules:
/// * UMP (GDPR) consent is gathered before the SDK is initialised
/// * no non-rewarded ad during the first 60s after the very first launch
/// * at least 120s between any two full-screen ads (incl. rewarded)
/// * interstitial after every 3 finished games
/// * App Open when returning from background (same 120s gap)
/// * rewarded ads are only ever shown when the player taps a button
/// * "Remove Ads" purchase disables banner / interstitial / app open only
class AdService {
  static const minGap = Duration(seconds: 120);
  static const firstRunGrace = Duration(seconds: 60);
  static const roundsPerInterstitial = 3;

  AdService(this.storage);

  final StorageService storage;

  /// Becomes true once consent is resolved and the SDK is initialised.
  final ready = ValueNotifier<bool>(false);

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  AppOpenAd? _appOpen;
  DateTime? _lastFullScreen;
  bool _showingFullScreen = false;
  bool _skipNextAppOpen = false;
  int _rounds = 0;
  StreamSubscription<AppState>? _appStateSub;

  bool get canShowRewarded => ready.value && _rewarded != null;

  /// Time left in the first-launch "no ads" window.
  Duration get graceRemaining {
    final left =
        firstRunGrace.inMilliseconds -
        (DateTime.now().millisecondsSinceEpoch - storage.firstLaunch);
    return left > 0 ? Duration(milliseconds: left) : Duration.zero;
  }

  bool get _gapOk =>
      _lastFullScreen == null ||
      DateTime.now().difference(_lastFullScreen!) >= minGap;

  bool get _nonRewardedAllowed =>
      ready.value && !storage.adsRemoved && graceRemaining == Duration.zero;

  /// Gathers GDPR consent (UMP) first, then initialises the SDK.
  Future<void> init() async {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) {
        if (!completer.isCompleted) completer.complete();
      }),
      (_) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {},
    );
    if (!await ConsentInformation.instance.canRequestAds()) return;

    await MobileAds.instance.initialize();
    ready.value = true;
    _loadInterstitial();
    _loadRewarded();
    _loadAppOpen();
    AppStateEventNotifier.startListening();
    _appStateSub = AppStateEventNotifier.appStateStream.listen((s) {
      if (s == AppState.foreground) _showAppOpen();
    });
  }

  /// Whether the "Privacy options" entry must be shown in settings
  /// (required by UMP for users in the EEA/UK).
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  void showPrivacyOptions() {
    skipNextAppOpen();
    ConsentForm.showPrivacyOptionsForm((_) {});
  }

  /// Call before leaving the app on purpose (store purchase, browser link)
  /// so returning does not trigger an App Open ad.
  void skipNextAppOpen() => _skipNextAppOpen = true;

  void dispose() {
    _appStateSub?.cancel();
    _interstitial?.dispose();
    _rewarded?.dispose();
    _appOpen?.dispose();
  }

  // ---------------- Banner ----------------

  /// Returns a loading banner, or null when banners are not allowed yet.
  BannerAd? createBanner(VoidCallback onLoaded) {
    if (!_nonRewardedAllowed) return null;
    return BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded(),
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    )..load();
  }

  // ---------------- Interstitial ----------------
  void _loadInterstitial() {
    if (storage.adsRemoved) return;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  /// Call once after every finished game (win or final loss).
  void onRoundFinished() {
    _rounds++;
    if (_rounds % roundsPerInterstitial != 0) return;
    final ad = _interstitial;
    if (ad == null || !_nonRewardedAllowed || !_gapOk || _showingFullScreen) {
      // Try again on the next finished game instead of waiting 3 more.
      _rounds--;
      if (ad == null) _loadInterstitial();
      return;
    }
    _interstitial = null;
    ad.fullScreenContentCallback = _fullScreenCallback(_loadInterstitial);
    ad.show();
  }

  // ---------------- Rewarded ----------------
  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) {
          _rewarded = null;
          Future.delayed(const Duration(seconds: 30), () {
            if (_rewarded == null) _loadRewarded();
          });
        },
      ),
    );
  }

  /// Shows a rewarded ad (always player-initiated). Completes with true
  /// only if the reward was earned.
  Future<bool> showRewarded() {
    final ad = _rewarded;
    if (ad == null || _showingFullScreen) {
      if (ad == null && ready.value) _loadRewarded();
      return Future.value(false);
    }
    _rewarded = null;
    final result = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = _fullScreenCallback(() {
      _loadRewarded();
      if (!result.isCompleted) result.complete(earned);
    });
    ad.show(onUserEarnedReward: (_, _) => earned = true);
    return result.future;
  }

  // ---------------- App Open ----------------
  void _loadAppOpen() {
    if (storage.adsRemoved) return;
    AppOpenAd.load(
      adUnitId: AdIds.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) => _appOpen = ad,
        onAdFailedToLoad: (_) => _appOpen = null,
      ),
    );
  }

  void _showAppOpen() {
    if (_skipNextAppOpen) {
      _skipNextAppOpen = false;
      return;
    }
    final ad = _appOpen;
    if (_showingFullScreen || !_nonRewardedAllowed || !_gapOk) return;
    if (ad == null) {
      _loadAppOpen();
      return;
    }
    _appOpen = null;
    ad.fullScreenContentCallback = _fullScreenCallback(_loadAppOpen);
    ad.show();
  }

  FullScreenContentCallback<T> _fullScreenCallback<T extends Ad>(
    VoidCallback onDone,
  ) {
    return FullScreenContentCallback<T>(
      onAdShowedFullScreenContent: (_) {
        _showingFullScreen = true;
        _lastFullScreen = DateTime.now();
      },
      onAdDismissedFullScreenContent: (ad) {
        _showingFullScreen = false;
        _lastFullScreen = DateTime.now();
        ad.dispose();
        onDone();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _showingFullScreen = false;
        ad.dispose();
        onDone();
      },
    );
  }
}
