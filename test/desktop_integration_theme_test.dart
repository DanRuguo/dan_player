import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/taskbar_song_preview.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('live theme changes update native icons and song text without a skip',
      () async {
    final theme = ThemeProvider.forTesting(
      seedColor: Colors.teal,
      dynamicThemeEnabled: () => true,
      loadArtwork: (_) async => null,
      extractScheme: (_, brightness) async =>
          ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness),
    );
    final native = FakeDesktopNative();
    final playback = FakeDesktopPlayback();
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    final rendered = <(ColorScheme, String)>[];
    final integration = DesktopIntegration.forTesting(
      native: native,
      window: FakeDesktopWindow(native),
      playback: playback,
      preferences: preferences,
      syncAppearance: true,
      themeProvider: theme,
      previewRenderer: (_, colors, font) async {
        rendered.add((colors, font));
        return TaskbarThumbnail(1, 1, Uint8List.fromList([0, 0, 0, 255]));
      },
    );
    addTearDown(() async {
      await integration.dispose();
      playback.dispose();
      preferences.dispose();
      theme.dispose();
    });
    await integration.initialize(onExit: () async {});
    final initialNative =
        native.calls.lastWhere((e) => e.$1 == 'configure').$2!;
    expect(initialNative['fontFamily'], danEmbeddedFontFamily);
    expect(initialNative['fontPath'],
        endsWith('assets\\fonts\\PingFangSC-Regular.ttf'));
    playback.value = const DesktopPlaybackSnapshot(
      ready: true,
      hasTrack: true,
      preview: TaskbarPreviewTrack(
          identity: 'same', title: '同一首歌', artist: '艺术家', album: '专辑'),
    );
    await flushDesktopEvents();
    final original = rendered.single.$1;
    theme.applyTheme(seedColor: Colors.deepOrange);
    await flushDesktopEvents();
    expect(rendered.last.$1.primary, theme.currScheme.primary);
    expect(rendered.last.$1.onSurface, theme.currScheme.onSurface);
    expect(rendered.last.$1.primary, isNot(original.primary));
    final argb = theme.currScheme.primary.toARGB32();
    expect(native.calls.lastWhere((e) => e.$1 == 'configure').$2!['accent'],
        ((argb >> 16) & 255) | (argb & 0xff00) | ((argb & 255) << 16));
    theme.applyThemeMode(ThemeMode.dark);
    await flushDesktopEvents();
    expect(rendered.last.$1.brightness, Brightness.dark);
    expect(
        native.calls.lastWhere((e) => e.$1 == 'configure').$2!['dark'], true);
    theme.changeFontFamily('SelectedFont');
    await flushDesktopEvents();
    expect(rendered.last.$2, 'SelectedFont');
    expect(native.calls.lastWhere((e) => e.$1 == 'configure').$2!['fontFamily'],
        'SelectedFont');
    expect(
        native.calls.lastWhere((e) => e.$1 == 'configure').$2!['fontPath'], '');
    final settings = AppSettings.instance;
    final previousFamily = settings.fontFamily;
    final previousPath = settings.fontPath;
    addTearDown(() {
      settings.fontFamily = previousFamily;
      settings.fontPath = previousPath;
    });
    settings.fontFamily = 'Another selected family';
    settings.fontPath = 'D:\\Fonts\\自选字体.ttf';
    theme.changeFontFamily(settings.fontFamily);
    await flushDesktopEvents();
    final customNative = native.calls.lastWhere((e) => e.$1 == 'configure').$2!;
    expect(customNative['fontFamily'], settings.fontFamily);
    expect(customNative['fontPath'], settings.fontPath);
    theme.changeFontFamily(null);
    await flushDesktopEvents();
    expect(native.calls.lastWhere((e) => e.$1 == 'configure').$2!['fontFamily'],
        danEmbeddedFontFamily);
    final count = rendered.length;
    await integration.dispose();
    theme.applyTheme(seedColor: Colors.purple);
    await flushDesktopEvents();
    expect(rendered, hasLength(count));
  });
}
