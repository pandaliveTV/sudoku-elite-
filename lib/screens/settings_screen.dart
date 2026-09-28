import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/strings.dart';
import '../services/ad_service.dart';
import '../services/iap_service.dart';
import '../services/storage_service.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _privacyOptions = false;

  @override
  void initState() {
    super.initState();
    final ads = context.read<AdService>();
    if (ads.ready.value) {
      ads.privacyOptionsRequired().then((v) {
        if (mounted) setState(() => _privacyOptions = v);
      });
    }
  }

  Future<void> _chooseLanguage(StorageService s) async {
    final options = {
      'system': context.tr('lang_system'),
      'ar': 'العربية',
      'en': 'English',
    };
    final v = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(c.tr('language')),
        children: [
          RadioGroup<String>(
            groupValue: s.language,
            onChanged: (v) => Navigator.pop(c, v),
            child: Column(
              children: [
                for (final e in options.entries)
                  RadioListTile<String>(value: e.key, title: Text(e.value)),
              ],
            ),
          ),
        ],
      ),
    );
    if (v != null) s.setLanguage(v);
  }

  Future<void> _buy() async {
    final messenger = ScaffoldMessenger.of(context);
    final msg = context.tr('store_unavailable');
    context.read<AdService>().skipNextAppOpen();
    final ok = await context.read<IapService>().buyRemoveAds();
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<StorageService>();
    final iap = context.read<IapService>();
    final langLabel = switch (s.language) {
      'ar' => 'العربية',
      'en' => 'English',
      _ => context.tr('lang_system'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: MaxWidth(
        child: ListView(
          children: [
            SwitchListTile(
              title: Text(context.tr('sound')),
              secondary: Icon(s.muted ? Icons.volume_off : Icons.volume_up),
              value: !s.muted,
              onChanged: (v) => s.setMuted(!v),
            ),
            SwitchListTile(
              title: Text(context.tr('vibration')),
              secondary: const Icon(Icons.vibration),
              value: s.vibration,
              onChanged: s.setVibration,
            ),
            SwitchListTile(
              title: Text(context.tr('highlight_same')),
              secondary: const Icon(Icons.filter_9_plus_outlined),
              value: s.highlightSame,
              onChanged: s.setHighlightSame,
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(context.tr('language')),
              subtitle: Text(langLabel),
              onTap: () => _chooseLanguage(s),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(
                s.adsRemoved
                    ? context.tr('ads_removed')
                    : context.tr('remove_ads'),
              ),
              subtitle: s.adsRemoved
                  ? null
                  : Text(
                      [
                        context.tr('remove_ads_desc'),
                        ?iap.product?.price,
                      ].join(' • '),
                    ),
              onTap: s.adsRemoved ? null : _buy,
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(context.tr('restore')),
              onTap: () {
                context.read<AdService>().skipNextAppOpen();
                iap.restore();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(context.tr('privacy_policy')),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => openPrivacyPolicy(context),
            ),
            if (_privacyOptions)
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: Text(context.tr('privacy_options')),
                onTap: context.read<AdService>().showPrivacyOptions,
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(context.tr('about')),
              subtitle: Text(context.tr('version', {'v': appVersion})),
            ),
          ],
        ),
      ),
    );
  }
}
