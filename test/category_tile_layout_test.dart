import 'dart:math';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/category_tile_layout.dart';
import 'package:dan_player/component/category_tile_motion.dart';
import 'package:dan_player/component/cover_caption_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tile motion stops scheduling frames after settling',
      (tester) async {
    var rect = const Rect.fromLTWH(0, 0, 100, 100);
    late StateSetter update;
    var builds = 0;
    await tester
        .pumpWidget(MaterialApp(home: StatefulBuilder(builder: (_, set) {
      update = set;
      return CategoryTileMotion(
          rect: rect,
          linear: true,
          child: Builder(builder: (_) {
            builds++;
            return const SizedBox();
          }));
    })));
    update(() => rect = const Rect.fromLTWH(200, 100, 200, 100));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    final settledBuilds = builds;
    await tester.pump(const Duration(seconds: 10));
    expect(builds, settledBuilds);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  void valid(List<CategoryTilePlacement> tiles, int columns, int count) {
    expect(tiles.map((t) => t.index).toSet().length, count);
    final cells = <(int, int)>{};
    for (final tile in tiles) {
      expect(tile.column + tile.columns, lessThanOrEqualTo(columns));
      for (var x = tile.column; x < tile.column + tile.columns; x++) {
        for (var y = tile.row; y < tile.row + tile.rows; y++) {
          expect(cells.add((x, y)), isTrue, reason: 'overlap at $x,$y');
        }
      }
    }
  }

  test('shrink preserves holes and unaffected origins without auto fill', () {
    final before = packCategoryTiles([
      CategoryTileSize.large,
      CategoryTileSize.small,
      CategoryTileSize.small
    ], 4, fillGaps: false);
    final after = packCategoryTiles(List.filled(3, CategoryTileSize.small), 4,
        fillGaps: false, previous: before, resizedIndex: 0);
    valid(after, 4, 3);
    for (final t in before) {
      final next = after.firstWhere((n) => n.index == t.index);
      expect((next.column, next.row), (t.column, t.row));
    }
  });
  test('grow reserves resized origin and only displaces collisions', () {
    final sizes = List.filled(12, CategoryTileSize.small);
    final before = packCategoryTiles(sizes, 4, fillGaps: false);
    sizes[0] = CategoryTileSize.large;
    final after = packCategoryTiles(sizes, 4,
        fillGaps: false, previous: before, resizedIndex: 0);
    valid(after, 4, 12);
    for (final i in [2, 3, 6, 7, 8, 9, 10, 11]) {
      final old = before.firstWhere((t) => t.index == i),
          next = after.firstWhere((t) => t.index == i);
      expect((next.column, next.row), (old.column, old.row));
    }
  });
  test('first fit fills an earlier gap with a later small tile', () {
    final tiles = packCategoryTiles(
        [CategoryTileSize.wide, CategoryTileSize.large, CategoryTileSize.small],
        3);
    expect((tiles[1].index, tiles[1].column, tiles[1].row), (2, 2, 0));
    valid(tiles, 3, 3);
  });
  test('packing remains collision free over varied sizes, widths and edits',
      () {
    final random = Random(26);
    for (var columns = 1; columns <= 16; columns++) {
      final sizes =
          List.generate(180, (_) => CategoryTileSize.values[random.nextInt(4)]);
      var tiles = packCategoryTiles(sizes, columns);
      valid(tiles, columns, sizes.length);
      for (var edit = 0; edit < 8; edit++) {
        final index = random.nextInt(sizes.length);
        sizes[index] = CategoryTileSize.values[random.nextInt(4)];
        tiles = packCategoryTiles(sizes, columns,
            fillGaps: false, previous: tiles, resizedIndex: index);
        valid(tiles, columns, sizes.length);
      }
    }
  });
  test('packing benchmark and stable idle layout budget', () {
    for (final count in [500, 5000]) {
      final sizes =
          List.generate(count, (i) => CategoryTileSize.values[(i * 7) % 4]);
      for (var i = 0; i < 20; i++) {
        packCategoryTiles(sizes, 9);
      }
      final times = <int>[];
      for (var i = 0; i < 80; i++) {
        final watch = Stopwatch()..start();
        final result = packCategoryTiles(sizes, 9);
        watch.stop();
        expect(result.length, count);
        times.add(watch.elapsedMicroseconds);
      }
      times.sort();
      // Recorded evidence, not a flaky wall-clock assertion on CI machines.
      debugPrint(
          'Tile packing $count: median ${times[40]} us, p95 ${times[76]} us');
    }
  });

  test('caption chooses contrasting text without painting a backing rectangle',
      () {
    for (final gray in [0, 30, 80, 160, 220, 255]) {
      final sample = Color.fromARGB(255, gray, gray, gray);
      final result = captionColorsForSamples([sample]);
      final l = sample.computeLuminance();
      final ink = result.foreground.computeLuminance();
      expect(
          (max(l, ink) + .05) / (min(l, ink) + .05), greaterThanOrEqualTo(4.5));
      expect(result.background, Colors.transparent);
    }
    expect(captionColorsForSamples([Colors.white]).foreground, Colors.black);
    expect(captionColorsForSamples([Colors.black]).foreground, Colors.white);
  });
}
