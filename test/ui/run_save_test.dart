import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/session.dart';
import 'package:rotathree/ui/data/run_save.dart';
import 'package:rotathree/ui/data/stats.dart';
import 'package:rotathree/ui/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a complete game save survives storage, including a pending level', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.open();
    const session = CampaignSession(0);
    final engine = GameEngine(config: planFor(session).config)..state.score = 1200;
    final save = RunSave(
      id: 'saved-1',
      session: session,
      engine: engine.snapshot(),
      carry: RunTotals.none,
      levelBase: 0,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      banner: const SavedBanner(kicker: 'Уровень 1 пройден', title: '1200', left: 1.7, blocking: true, pendingLevel: 1),
    );
    expect(await store.saveRun(save), isTrue);
    final again = (await AppStore.open()).loadRun()!;
    expect(jsonEncode(again.toJson()), jsonEncode(save.toJson()));
    final run = again.abandoned();
    expect(run.interrupted, isTrue);
    final stats = Stats.empty().withRun(run);
    expect(stats.withRun(run), same(stats));
    expect(await store.saveRun(null), isTrue);
    expect(store.loadRun(), isNull);
  });
  test('unavailable storage retains data in memory and reports failed writes', () async {
    final store = AppStore(null);
    expect(store.available, isFalse);
    expect(await store.saveTutorial(true), isFalse);
    expect(store.loadTutorial(), isTrue);
  });
}
