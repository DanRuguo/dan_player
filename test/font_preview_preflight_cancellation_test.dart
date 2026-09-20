import 'dart:async';

import 'package:dan_player/component/font_preview_loader.dart';
import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:flutter_test/flutter_test.dart';

const firstFont = InstalledFont(path: 'first.ttf', fullName: 'First');
const nextFont = InstalledFont(path: 'next.ttf', fullName: 'Next');

void main() {
  for (final explicit in [false, true]) {
    test(
        'released preview during file check skips registration explicit=$explicit',
        () async {
      final checked = Completer<void>();
      final size = Completer<int>();
      final loaded = <InstalledFont>[];
      final loader = FontPreviewLoader(
        maximumAutomaticFonts: 1,
        maximumAutomaticBytes: 64,
        sizeOf: (font) {
          if (font == firstFont) {
            checked.complete();
            return size.future;
          }
          return Future.value(64);
        },
        load: (font) async => loaded.add(font),
      );
      final preview = loader.acquire(firstFont, explicit: explicit);
      await checked.future;
      preview.release();
      size.complete(64);
      expect(await preview.family, isNull);
      expect(loaded, isEmpty,
          reason: 'Closing or scrolling away must not register unused fonts');
      final next = loader.acquire(nextFont);
      expect(await next.family, nextFont.fullName,
          reason: 'Cancelled previews must leave the automatic budget intact');
      expect(loaded, [nextFont]);
      next.release();
    });
  }

  test('another visible consumer keeps an in-flight preview alive', () async {
    final checked = Completer<void>();
    final size = Completer<int>();
    var loads = 0;
    var checks = 0;
    final loader = FontPreviewLoader(
      sizeOf: (_) {
        checks++;
        checked.complete();
        return size.future;
      },
      load: (_) async => loads++,
    );
    final row = loader.acquire(firstFont);
    await checked.future;
    row.release();
    // The selected preview still needs this font even if its row scrolls away.
    final selected = loader.acquire(firstFont, explicit: true);
    size.complete(64);
    expect(await selected.family, firstFont.fullName);
    expect(checks, 1);
    expect(loads, 1);
    selected.release();
  });
}
