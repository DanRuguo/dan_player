import 'dart:async';
import 'dart:typed_data';

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/taskbar_song_preview.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

const _track = TaskbarPreviewTrack(
    identity: 'same-song', title: 'TRACK', artist: 'ARTIST', album: 'ALBUM');
const _textRegions = <String, Rect>{
  'title': Rect.fromLTRB(220, 35, 456, 94),
  'artist': Rect.fromLTRB(220, 104, 456, 153),
  'album': Rect.fromLTRB(220, 162, 456, 188),
  'brand': Rect.fromLTRB(220, 199, 456, 230),
};

int _argb(TaskbarThumbnail card, int x, int y) {
  final offset = (y * card.width + x) * 4;
  return (card.pixels[offset + 3] << 24) |
      (card.pixels[offset] << 16) |
      (card.pixels[offset + 1] << 8) |
      card.pixels[offset + 2];
}

Map<int, int> _histogram(TaskbarThumbnail card, Rect bounds) {
  final counts = <int, int>{};
  for (var y = bounds.top.toInt(); y < bounds.bottom; y++) {
    for (var x = bounds.left.toInt(); x < bounds.right; x++) {
      final color = _argb(card, x, y);
      counts.update(color, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return counts;
}

void _expectAccentText(TaskbarThumbnail card, ColorScheme scheme) {
  for (final entry in _textRegions.entries) {
    // Inspect actual production RGBA pixels, not an injected renderer. Each
    // separate text row must contain solid accent glyphs (besides antialiasing).
    expect(_histogram(card, entry.value)[scheme.primary.toARGB32()] ?? 0,
        greaterThan(20),
        reason: '${entry.key} must use the current artwork/theme primary');
  }
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness all four text rows change with the primary only',
        (tester) async {
      final first =
          ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness);
      final second = first.copyWith(
          primary: ColorScheme.fromSeed(
                  seedColor: Colors.deepOrange, brightness: brightness)
              .primary);
      final cards = await tester.runAsync(() async => [
            await renderTaskbarSongPreview(
                _track, first, danEmbeddedFontFamily),
            await renderTaskbarSongPreview(
                _track, second, danEmbeddedFontFamily),
          ]);
      _expectAccentText(cards![0], first);
      _expectAccentText(cards[1], second);
      expect(first.primary, isNot(second.primary));
      // The metadata, opaque background, cover placeholder and layout did not
      // change. Only the text/accent field changes in this isolated regression.
      for (var y = 0; y < 240; y++) {
        // Leave the text's glyph/antialias overhang outside this cover region.
        for (var x = 0; x < 210; x++) {
          if (_argb(cards[1], x, y) != _argb(cards[0], x, y)) {
            fail('Non-text preview pixel changed at ($x, $y)');
          }
        }
      }
    });

    testWidgets('$brightness low-contrast custom primary remains readable',
        (tester) async {
      final surface =
          brightness == Brightness.light ? Colors.white : Colors.black;
      final primary = brightness == Brightness.light
          ? const Color(0xffffeeee)
          : const Color(0xff220000);
      final scheme =
          ColorScheme.fromSeed(seedColor: Colors.red, brightness: brightness)
              .copyWith(surface: surface, primary: primary);
      expect(_contrast(primary, surface), lessThan(4.5));
      final card = await tester.runAsync(() =>
          renderTaskbarSongPreview(_track, scheme, danEmbeddedFontFamily));
      int? previous;
      for (final entry in _textRegions.entries) {
        final colors = _histogram(card!, entry.value)
          ..remove(surface.toARGB32());
        final solid =
            colors.entries.reduce((a, b) => a.value >= b.value ? a : b);
        final foreground = Color(solid.key);
        expect(solid.value, greaterThan(20));
        expect(_contrast(foreground, surface), greaterThanOrEqualTo(4.5));
        expect(foreground.r, greaterThan(foreground.g),
            reason: 'Keep the red accent instead of replacing it with neutral');
        expect(foreground.g, foreground.b);
        if (previous != null) expect(solid.key, previous);
        previous = solid.key;
      }
    });
  }

  testWidgets('live artwork, mode and font changes publish recolored pixels',
      (tester) async {
    final theme = ThemeProvider.forTesting(
        seedColor: Colors.teal,
        dynamicThemeEnabled: () => true,
        loadArtwork: (_) async => const AssetImage('synthetic-theme-only'),
        extractScheme: (_, brightness) async => ColorScheme.fromSeed(
            seedColor: Colors.deepOrange, brightness: brightness));
    final native = FakeDesktopNative();
    final playback = FakeDesktopPlayback();
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    late Completer<TaskbarThumbnail> received;
    native.intercept = (method, arguments) async {
      if (method == 'setThumbnail') {
        final ready = received;
        received = Completer<TaskbarThumbnail>();
        ready.complete(TaskbarThumbnail(arguments!['width'] as int,
            arguments['height'] as int, arguments['pixels'] as Uint8List));
      }
      return native.state();
    };
    final integration = DesktopIntegration.forTesting(
        native: native,
        window: FakeDesktopWindow(native),
        playback: playback,
        preferences: preferences,
        syncAppearance: true,
        themeProvider: theme);
    addTearDown(() async {
      await integration.dispose();
      preferences.dispose();
      playback.dispose();
      theme.dispose();
    });
    Future<TaskbarThumbnail> publish(FutureOr<void> Function() update) async {
      final next = received.future;
      await update();
      return next.timeout(const Duration(seconds: 5));
    }

    await tester.runAsync(() async {
      // Create this native-render completion in the real async zone, otherwise
      // a fake-clock microtask can remain parked while Picture.toImage runs.
      received = Completer<TaskbarThumbnail>();
      await integration.initialize(onExit: () async {});
      final initial = await publish(() {
        playback.value = const DesktopPlaybackSnapshot(
            ready: true, hasTrack: true, hasQueue: true, preview: _track);
      });
      _expectAccentText(initial, theme.currScheme);
      final initialColor = theme.currScheme.primary;
      // Palette extraction is synthetic; the actual card renderer and native
      // payload remain real. No album file, desktop capture or GUI is opened.
      final artwork = await publish(() => theme.applyThemeFromAudio(
          Audio.online(
              provider: 'test',
              id: 'same-song',
              title: 'TRACK',
              artist: 'ARTIST',
              album: 'ALBUM',
              duration: 120,
              created: 1)));
      expect(theme.currScheme.primary, isNot(initialColor));
      _expectAccentText(artwork, theme.currScheme);
      final dark = await publish(() => theme.applyThemeMode(ThemeMode.dark));
      _expectAccentText(dark, theme.currScheme);
      final font = await publish(() => theme.changeFontFamily('Ahem'));
      _expectAccentText(font, theme.currScheme);
      expect(playback.value.preview, same(_track));
      expect(native.calls.where((call) => call.$1 == 'setThumbnail'),
          hasLength(4));
      expect(integration.previewError, isNull);
    });
  });
}
