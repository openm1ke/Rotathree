import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/piece_generator.dart';
import 'package:rotathree/game/model/piece.dart';
import 'package:rotathree/game/model/position.dart';

import 'helpers.dart';

void main() {
  group('Piece', () {
    test('horizontal stick spans three lanes in one row', () {
      final piece = horizontal([r, b, y]);
      expect(piece.isHorizontal, isTrue);
      expect(piece.width, 3);
      expect(piece.depth, 1);
      expect(piece.offsets, const [
        CellPosition(0, 0),
        CellPosition(0, 1),
        CellPosition(0, 2),
      ]);
    });

    test('vertical stick spans three rows in one lane', () {
      final piece = vertical([r, b, y]);
      expect(piece.isVertical, isTrue);
      expect(piece.width, 1);
      expect(piece.depth, 3);
      expect(piece.offsets, const [
        CellPosition(0, 0),
        CellPosition(1, 0),
        CellPosition(2, 0),
      ]);
    });

    test('rotate horizontal → vertical', () {
      final rotated = horizontal([r, b, y]).rotated();
      expect(rotated.orientation, PieceOrientation.vertical);
      expect(rotated, vertical([r, b, y]));
    });

    test('rotate vertical → horizontal, now the other way round', () {
      final rotated = vertical([r, b, y]).rotated();
      expect(rotated.orientation, PieceOrientation.horizontalFlipped);
      expect(rotated.isHorizontal, isTrue);
      // The first colour has moved from the top to the right-hand end.
      expect(rotated.offsets.first, const CellPosition(0, 2));
      expect(rotated.offsets.last, const CellPosition(0, 0));
    });

    test('four quarter turns visit left, top, right, bottom and come back', () {
      // Where the first (red) square sits after each clockwise turn.
      var piece = horizontal([r, b, y]);
      final firstSquare = <CellPosition>[];
      final shapes = <bool>[];
      for (var i = 0; i < 4; i++) {
        firstSquare.add(piece.offsets.first);
        shapes.add(piece.isHorizontal);
        piece = piece.rotated();
      }
      expect(firstSquare, const [
        CellPosition(0, 0), // left
        CellPosition(0, 0), // top
        CellPosition(0, 2), // right
        CellPosition(2, 0), // bottom
      ]);
      expect(shapes, [true, false, true, false]);
      expect(piece, horizontal([r, b, y]));
    });

    test('turning back undoes a turn', () {
      final piece = horizontal([r, b, y]);
      expect(piece.rotated().rotatedBack(), piece);
      expect(piece.rotatedBack().orientation, PieceOrientation.verticalFlipped);
      expect(piece.rotatedBack().rotated(), piece);
    });

    test('the squares are never rearranged, only turned as a whole', () {
      var piece = horizontal([r, r, b]);
      for (var i = 0; i < 7; i++) {
        piece = piece.rotated();
        expect(piece.colors, [r, r, b]);
        // The middle square is always the middle one.
        expect(piece.offsets[1], anyOf(const CellPosition(0, 1), const CellPosition(1, 0)));
      }
    });

    test('colours cannot be reordered after creation', () {
      final source = [r, b, y];
      final piece = horizontal(source);
      source[0] = y;
      expect(piece.colors, [r, b, y]);
      expect(() => piece.colors[0] = y, throwsUnsupportedError);
    });
  });

  group('PieceGenerator', () {
    test('is deterministic for a seed', () {
      const config = GameConfig(seed: 42);
      final a = PieceGenerator(config);
      final b = PieceGenerator(config);
      for (var i = 0; i < 50; i++) {
        expect(a.next(), b.next());
      }
    });

    test('rolls horizontal sticks of the configured length and palette', () {
      const config = GameConfig(seed: 3, numberOfColors: 3);
      final generator = PieceGenerator(config);
      for (var i = 0; i < 300; i++) {
        final piece = generator.next();
        expect(piece.length, 3);
        expect(piece.isHorizontal, isTrue);
        expect(piece.colors.every([r, b, y].contains), isTrue);
      }
    });

    test('uses the fourth colour when four are configured', () {
      const config = GameConfig(seed: 3, numberOfColors: 4);
      final generator = PieceGenerator(config);
      final seen = {for (var i = 0; i < 300; i++) ...generator.next().colors};
      expect(seen, {r, b, y, g});
    });

    test('single-colour sticks are allowed but rarer than a fair roll', () {
      int monoCount(double keepChance) {
        final config = GameConfig(seed: 11, monoPieceKeepChance: keepChance);
        final generator = PieceGenerator(config);
        var mono = 0;
        for (var i = 0; i < 3000; i++) {
          if (generator.next().colors.toSet().length == 1) mono++;
        }
        return mono;
      }

      final fair = monoCount(1.0);
      final biased = monoCount(0.4);
      expect(fair, greaterThan(250)); // ~1/9 of 3000
      expect(biased, greaterThan(0));
      expect(biased, lessThan(fair * 0.6));
      expect(monoCount(0.0), 0);
    });
  });
}
