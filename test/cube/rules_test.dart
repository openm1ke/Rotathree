import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/cube/rules.dart';

// The rules' own checks, as webapp/src/tests/cube.test.ts has them.

void run(CubeGame game, double seconds) {
  for (var t = 0.0; t < seconds; t += 0.02) {
    game.update(0.02);
  }
}

int sideOf(int axis, int sign) => sides.indexWhere((s) => s.axis == axis && s.sign == sign);
final front = sideOf(2, 1);
final back = sideOf(2, -1);
final left = sideOf(0, -1);
final right = sideOf(0, 1);

/// ↑: data −Z comes on top; data +Y now looks at the eye.
void tipUp(CubeGame game) => game.turn(sideOf(2, -1), const Vec(0, 1, 0), const ViewFrame(Vec(1, 0, 0), Vec(0, 0, -1)), true);

void main() {
  group('the picture is the board', () {
    test('stops the stick on top on a block seen behind it', () {
      final game = CubeGame(const CubeConfig(seed: 4, inactiveFalls: false));
      final h = game.half;
      game.hub.set(game.cellAt(0, -h, -2), 1);
      final top = game.activePiece!
        ..pivot = game.cellAt(0, h, 0)
        ..dir = const Vec(1, 0, 0);
      expect(game.screenOf(game.restRow(top)).$2, -h + 1);
    });

    test('pops a line of what is seen, whatever the depths, and not one broken by a nearer block', () {
      final game = CubeGame(const CubeConfig(seed: 5, inactiveFalls: false));
      final h = game.half;
      game.hub.set(game.cellAt(-1, -h, 2), 3);
      game.hub.set(game.cellAt(0, -h, -3), 3);
      game.hub.set(game.cellAt(1, -h, 0), 3);
      game.hub.set(game.cellAt(0, -h, -1), 2);
      expect(game.findMatches().runs, isEmpty);
      game.hub.set(game.cellAt(0, -h, -1), empty);
      final match = game.findMatches();
      expect(match.runs, hasLength(1));
      expect(match.cells, hasLength(3));
    });

    test('lets a cell of the picture fall with everything behind it', () {
      final game = CubeGame(const CubeConfig(seed: 6, inactiveFalls: false));
      final h = game.half;
      game.hub.set(game.cellAt(0, -h, 1), 0);
      game.hub.set(game.cellAt(0, -h, -2), 1);
      game.hub.set(game.cellAt(0, -h + 2, 3), 2);
      game.hub.set(game.cellAt(0, -h + 2, -1), 4);
      expect(game.settle(), hasLength(2));
      expect(game.hub.at(game.cellAt(0, -h + 1, 3)), 2);
      expect(game.hub.at(game.cellAt(0, -h + 1, -1)), 4);
    });
  });

  group('tipping the hub over', () {
    test('shows the tops of the old columns as the bottom line', () {
      final game = CubeGame(const CubeConfig(seed: 7, inactiveFalls: false));
      game.pieces.clear();
      final h = game.half;
      for (var sy = -h; sy < -h + 3; sy++) {
        game.hub.set(game.cellAt(-1, sy, 0), (sy + h).round());
      }
      game.hub.set(game.cellAt(1, -h, 0), 3);
      tipUp(game);
      run(game, 1);
      int? seen(double sx) {
        final p = game.seenAt(sx, -h);
        return p == null ? null : game.hub.at(p);
      }

      expect(seen(-1), 2);
      expect(seen(1), 3);
    });

    test('keeps the sticks on its axis where the screen showed them, and moves none on a turn in the screen', () {
      final game = CubeGame(const CubeConfig(seed: 5, inactiveFalls: false));
      final l = game.pieces[left]!
        ..pivot = game.cellAt(-9, 1, 0)
        ..dir = const Vec(1, 0, 0);
      final r = game.pieces[right]!;
      final before = [game.screenOf(l.pivot), game.screenOf(r.pivot)];
      tipUp(game);
      expect([game.screenOf(l.pivot), game.screenOf(r.pivot)], before);
      expect([l.dir.x, l.dir.z], [1, 0]);

      final other = CubeGame(const CubeConfig(seed: 6, inactiveFalls: false));
      String snapshot() => other.pieces.values.map((p) => '${p.pivot}|${p.dir}').join(' ');
      final was = snapshot();
      other.turn(left, const Vec(0, 0, 1), const ViewFrame(Vec(0, 1, 0), Vec(-1, 0, 0)), false);
      expect(snapshot(), was);
    });

    test('previews a tip without touching the game, and counts what would pop', () {
      final game = CubeGame(const CubeConfig(seed: 7, inactiveFalls: false));
      game.pieces.clear();
      final h = game.half;
      for (var sy = -h; sy < -h + 3; sy++) {
        game.hub.set(game.cellAt(-1, sy, 0), 0);
      }
      game.hub.set(game.cellAt(0, -h, 0), 0);
      game.hub.set(game.cellAt(1, -h, 0), 0);
      final version = game.hub.version;
      final preview = game.previewTurn(const Vec(0, 1, 0), const ViewFrame(Vec(1, 0, 0), Vec(0, 0, -1)));
      expect(game.hub.version, version);
      expect(preview.rounds, greaterThanOrEqualTo(1));
      expect(preview.popped, greaterThanOrEqualTo(3));
    });
  });

  group('the glasses in front and behind', () {
    test('lands a front stick in front, seen, and a back one behind, hidden', () {
      final game = CubeGame(const CubeConfig(seed: 8, inactiveFalls: false));
      for (final sx in [-1.0, 0.0, 1.0]) {
        game.hub.set(game.cellAt(sx, 0, 0), 1);
      }
      game.pieces[front]!.pivot = game.cellAt(0, 0, game.middle);
      game.pieces[back]!.pivot = game.cellAt(0, 0, -game.middle);
      expect([game.landing(front)!.layer, game.landing(front)!.count], [1, 3]);
      expect([game.landing(back)!.layer, game.landing(back)!.count], [-1, 0]);
    });

    test('waits until steered unless they may fall alone', () {
      final game = CubeGame(const CubeConfig(seed: 3));
      final start = game.pieces[front]!.pivot;
      run(game, 7);
      expect(game.pieces[front]!.pivot, start);
      game.config = game.config.copyWith(depthFalls: true);
      run(game, 6.5);
      expect(game.pieces[front]!.pivot.z, start.z - 1);
    });

    test('steers them in place', () {
      final game = CubeGame(const CubeConfig(seed: 3, inactiveFalls: false));
      game.control(front);
      final start = game.activePiece!.pivot;
      game.move(const Vec(0, -1, 0));
      expect(game.activePiece!.pivot, Vec(start.x, start.y - 1, start.z));
    });
  });

  group('a whole game', () {
    test('plays to the end with every glass taking turns', () {
      final game = CubeGame(const CubeConfig(
        seed: 9,
        ramp: CubeRamp(everyPoints: 500, factor: 0.9, minActive: 0.3, minInactive: 0.8),
      ));
      for (var i = 0; i < 3000 && !game.isGameOver; i++) {
        game
          ..control([0, back, front][i % 3])
          ..dropActive();
        run(game, 0.5);
      }
      expect(game.isGameOver, isTrue);
      expect(game.placed, greaterThan(5));
    });

    test('steps fast while soft drop is held', () {
      final game = CubeGame(const CubeConfig(seed: 2, inactiveFalls: false));
      final start = game.activePiece!.pivot.y;
      game.softDrop = true;
      run(game, 0.3);
      expect(start - game.activePiece!.pivot.y, greaterThan(3));
    });
  });

  group('sizes and the next sticks', () {
    test('gives each glass its own next stick', () {
      final game = CubeGame(const CubeConfig(seed: 12, inactiveFalls: false));
      final top = game.active;
      final coming = game.nextOf(top);
      final others = [for (final s in sides) if (s.id != top) game.nextOf(s.id)];
      game.dropActive();
      run(game, 1);
      expect(game.activePiece!.colors, coming);
      expect([for (final s in sides) if (s.id != top) game.nextOf(s.id)], others);
    });

    test('plays an even cube: the sticks across the screen fall in the nearer middle layer, before a tip and after', () {
      final game = CubeGame(const CubeConfig(seed: 13, centre: 10, arm: 9, inactiveFalls: false));
      expect(game.half, 4.5);
      expect(game.layer, 0.5);
      for (final piece in game.pieces.values) {
        if (game.inPlane(piece.side)) expect(game.depthOf(piece.pivot), 0.5);
      }
      // Three seen in a row at the bottom, at whole and half depths alike.
      final h = game.half;
      for (final sx in [-1.5, -0.5, 0.5]) {
        game.hub.set(game.cellAt(sx, -h, sx + 1), 1);
      }
      expect(game.findMatches().runs, hasLength(1));
      final top = sideOf(1, 1);
      for (var i = 0; i < 3000 && !game.isGameOver; i++) {
        if (i % 7 == 3) {
          if (i.isOdd) {
            game.turn(back, const Vec(0, 1, 0), const ViewFrame(Vec(1, 0, 0), Vec(0, 0, -1)), true);
          } else {
            game.turn(top, const Vec(0, 0, 1), const ViewFrame(Vec(1, 0, 0), Vec(0, 1, 0)), true);
          }
          run(game, 2);
          for (final piece in game.pieces.values) {
            if (game.inPlane(piece.side)) expect(game.depthOf(piece.pivot), 0.5, reason: 'glass ${piece.side}');
          }
        }
        game.dropActive();
        run(game, 0.5);
      }
      expect(game.isGameOver, isTrue);
      expect(game.placed, greaterThan(5));
    });
  });

  group('a game kept between visits', () {
    CubeGame played() {
      final game = CubeGame(const CubeConfig(seed: 14, centre: 10, arm: 6));
      for (var i = 0; i < 6; i++) {
        game.dropActive();
        run(game, 0.6);
      }
      game.turn(back, const Vec(0, 1, 0), const ViewFrame(Vec(1, 0, 0), Vec(0, 0, -1)), true);
      run(game, 2);
      return game;
    }

    test('comes back as it was left, turned and all, and plays on', () {
      final game = played();
      final snapshot = game.snapshot()!;
      final restored = CubeGame.restore(jsonDecode(jsonEncode(snapshot)));
      expect(restored.hub.cells, game.hub.cells);
      expect([restored.plane, restored.viewFrame, restored.down, restored.active], [game.plane, game.viewFrame, game.down, game.active]);
      String sticks(CubeGame g) => g.pieces.values.map((p) => '${p.side}:${p.colors}@${p.pivot}/${p.dir}/${p.progress}').join(' ');
      expect(sticks(restored), sticks(game));
      expect(restored.next, game.next);
      expect(
        [restored.score, restored.placed, restored.matches, restored.seconds, restored.speedLevel],
        [game.score, game.placed, game.matches, game.seconds, game.speedLevel],
      );
      restored.dropActive();
      run(restored, 1);
      expect(restored.placed, game.placed + 1);
    });

    test('keeps nothing in the middle of a move, and refuses what is not a game', () {
      final game = played();
      final snapshot = game.snapshot()!;
      game.dropActive();
      expect(game.snapshot(), isNull);
      expect(() => CubeGame.restore({...snapshot, 'blocks': [1e9, 0]}), throwsFormatException);
      expect(() => CubeGame.restore({...snapshot, 'plane': [0, 1, 1]}), throwsFormatException);
    });
  });
}
