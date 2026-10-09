import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/config/modes.dart';
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
  test('per-mode slots coexist and migrate an existing single save', () async {
    RunSave save(Session session, String id) => RunSave(
      id: id,
      session: session,
      engine: GameEngine(config: planFor(session).config).snapshot(),
      carry: RunTotals.none,
      levelBase: 0,
      savedAt: 100,
    );
    final campaign = save(const CampaignSession(0), 'campaign');
    final custom = save(const CustomSession(defaultCustom), 'custom');
    SharedPreferences.setMockInitialValues({'rotathree.run.mobile.v1': jsonEncode(campaign.toJson())});
    final store = await AppStore.open();
    expect(store.loadRuns().keys, [ModeId.campaign]);
    await store.saveRuns({ModeId.campaign: campaign, ModeId.custom: custom});
    final again = (await AppStore.open()).loadRuns();
    expect(again.keys, containsAll([ModeId.campaign, ModeId.custom]));
    await store.saveRuns({ModeId.custom: custom});
    expect(store.loadRuns().keys, [ModeId.custom]);
    expect(
      readSavedRuns({
        'version': 2,
        'runs': {
          'campaign': {'broken': true},
          'custom': custom.toJson(),
        },
      }).keys,
      [ModeId.custom],
    );
  });
  test('unavailable storage retains data in memory and reports failed writes', () async {
    final store = AppStore(null);
    expect(store.available, isFalse);
    expect(await store.saveTutorial(true), isFalse);
    expect(store.loadTutorial(), isTrue);
  });
}
