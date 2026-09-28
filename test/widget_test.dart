import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sudoku/data/difficulty.dart';
import 'package:sudoku/game/game_controller.dart';
import 'package:sudoku/game/sudoku_engine.dart';
import 'package:sudoku/main.dart';
import 'package:sudoku/screens/home_screen.dart';
import 'package:sudoku/services/ad_service.dart';
import 'package:sudoku/services/audio_service.dart';
import 'package:sudoku/services/iap_service.dart';
import 'package:sudoku/services/storage_service.dart';
import 'package:sudoku/widgets/sudoku_board.dart';

Future<Widget> app(Widget home, {String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues({'language': lang});
  final storage = StorageService();
  await storage.init();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: storage),
      Provider.value(value: AdService(storage)),
      Provider.value(value: IapService(storage)),
      Provider.value(value: AudioService(storage)),
    ],
    child: SudokuApp(home: home),
  );
}

void main() {
  testWidgets('home screen shows main menu (English)', (tester) async {
    await tester.pumpWidget(await app(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('SUDOKU'), findsOneWidget);
    expect(find.text('New Game'), findsOneWidget);
    expect(find.text('Daily Challenge'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('home screen is translated to Arabic (RTL)', (tester) async {
    await tester.pumpWidget(await app(const HomeScreen(), lang: 'ar'));
    await tester.pumpAndSettle();
    expect(find.text('لعبة جديدة'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.text('لعبة جديدة')));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('tapping the board selects a cell, pad enters digits', (
    tester,
  ) async {
    final game = GameController.fromPuzzle(
      SudokuGenerator.generate(Difficulty.easy, seed: 3),
    );
    await tester.pumpWidget(
      await app(
        Scaffold(
          body: ListenableBuilder(
            listenable: game,
            builder: (context, _) => Column(
              children: [
                SizedBox(
                  width: 360,
                  child: SudokuBoard(
                    game: game,
                    highlightSame: true,
                    onSelect: game.select,
                  ),
                ),
                NumberPad(game: game, onDigit: game.input),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final empty = game.values.indexOf(0);
    final topLeft = tester.getTopLeft(find.byType(SudokuBoard));
    const cell = 40.0;
    await tester.tapAt(
      topLeft + Offset((empty % 9 + 0.5) * cell, (empty ~/ 9 + 0.5) * cell),
    );
    await tester.pump();
    expect(game.selected, empty);
    await tester.tap(find.text('${game.solution[empty]}').last);
    await tester.pump();
    expect(game.values[empty], game.solution[empty]);
    game.dispose();
  });
}
