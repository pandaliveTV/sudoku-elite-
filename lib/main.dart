import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/splash_screen.dart';
import 'services/ad_service.dart';
import 'services/audio_service.dart';
import 'services/iap_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final storage = StorageService();
  await storage.init();
  final ads = AdService(storage);
  final iap = IapService(storage);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: storage),
        Provider.value(value: ads),
        Provider.value(value: iap),
        Provider.value(value: AudioService(storage)),
      ],
      child: const SudokuApp(),
    ),
  );
  // Consent (UMP) + SDK init run in the background so the splash is not
  // blocked; no ad is requested before consent is resolved.
  ads.init();
  iap.init();
}

class SudokuApp extends StatelessWidget {
  const SudokuApp({super.key, this.home = const SplashScreen()});

  final Widget home;

  static const seed = Color(0xFF3D5AFE);

  static ThemeData _theme(Brightness b) => ThemeData(
    brightness: b,
    colorSchemeSeed: seed,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: true),
  );

  @override
  Widget build(BuildContext context) {
    final lang = context.select<StorageService, String>((s) => s.language);
    return MaterialApp(
      title: 'Sudoku Elite',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: lang == 'system' ? null : Locale(lang),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      localeResolutionCallback: (locale, supported) => supported.firstWhere(
        (l) => l.languageCode == locale?.languageCode,
        orElse: () => const Locale('en'),
      ),
      home: home,
    );
  }
}
