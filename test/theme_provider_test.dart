import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _fallback = Colors.teal;
const _firstImage = AssetImage('first-cover');
const _secondImage = AssetImage('second-cover');

Audio _audio(String id) => Audio.online(
      provider: 'test',
      id: id,
      title: id,
      artist: 'Artist',
      album: 'Album',
      duration: 120,
      created: 1,
    );

Future<ColorScheme> _extract(
  ImageProvider image,
  Brightness brightness,
) async =>
    ColorScheme.fromSeed(
      seedColor: (image as ResizeImage).imageProvider == _firstImage
          ? Colors.blue
          : Colors.orange,
      brightness: brightness,
    );

void _expectDefault(ThemeProvider theme, [Color seed = _fallback]) {
  expect(theme.backdropImage, isNull);
  expect(
    theme.lightScheme,
    ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
  );
  expect(
    theme.darkScheme,
    ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unchanged track notifications reuse one cover and atomic palette',
      () async {
    var loads = 0;
    var notifications = 0;
    final theme = ThemeProvider.forTesting(
      seedColor: _fallback,
      dynamicThemeEnabled: () => true,
      loadArtwork: (_) async {
        loads++;
        return _firstImage;
      },
      extractScheme: _extract,
    );
    addTearDown(theme.dispose);
    theme.addListener(() {
      notifications++;
      expect(theme.backdropImage, isA<ResizeImage>());
      expect(theme.lightScheme.brightness, Brightness.light);
      expect(theme.darkScheme.brightness, Brightness.dark);
    });
    final audio = _audio('first');
    await Future.wait(
      List.generate(40, (_) => theme.applyThemeFromAudio(audio)),
    );
    expect(loads, 1);
    expect(notifications, 1);
    final backdrop = theme.backdropImage! as ResizeImage;
    expect(backdrop.imageProvider, _firstImage);
    expect((backdrop.width, backdrop.height), (320, 320));
    expect(backdrop.policy, ResizeImagePolicy.fit);
  });

  test('an in-place metadata revision reloads the same Audio object', () async {
    var loads = 0;
    final theme = ThemeProvider.forTesting(
      seedColor: _fallback,
      dynamicThemeEnabled: () => true,
      loadArtwork: (_) async => ++loads == 1 ? _firstImage : _secondImage,
      extractScheme: _extract,
    );
    addTearDown(theme.dispose);
    final audio = _audio('same-path');
    await theme.applyThemeFromAudio(audio);
    audio.modified++;
    await theme.applyThemeFromAudio(audio);
    expect(loads, 2);
    expect((theme.backdropImage! as ResizeImage).imageProvider, _secondImage);
    await theme.applyThemeFromAudio(audio);
    expect(loads, 2);
  });

  test('late cover loading cannot replace the next song', () async {
    final firstCover = Completer<ImageProvider?>();
    final theme = ThemeProvider.forTesting(
      seedColor: _fallback,
      dynamicThemeEnabled: () => true,
      loadArtwork: (audio) => audio.onlineId == 'first'
          ? firstCover.future
          : Future.value(_secondImage),
      extractScheme: _extract,
    );
    addTearDown(theme.dispose);
    final stale = theme.applyThemeFromAudio(_audio('first'));
    await theme.applyThemeFromAudio(_audio('second'));
    final current = theme.backdropImage;
    final currentScheme = theme.lightScheme;
    firstCover.complete(_firstImage);
    await stale;
    expect(theme.backdropImage, same(current));
    expect(theme.lightScheme, currentScheme);
  });

  test('late palette extraction cannot overwrite a new cover or dark mode',
      () async {
    final oldPalettes = <Brightness, Completer<ColorScheme>>{};
    final theme = ThemeProvider.forTesting(
      seedColor: _fallback,
      dynamicThemeEnabled: () => true,
      loadArtwork: (audio) async =>
          audio.onlineId == 'first' ? _firstImage : _secondImage,
      extractScheme: (image, brightness) {
        if ((image as ResizeImage).imageProvider == _firstImage) {
          final result = Completer<ColorScheme>();
          oldPalettes[brightness] = result;
          return result.future;
        }
        return _extract(image, brightness);
      },
    );
    addTearDown(theme.dispose);
    final stale = theme.applyThemeFromAudio(_audio('first'));
    await Future<void>.delayed(Duration.zero);
    expect(oldPalettes.length, 2);
    await theme.applyThemeFromAudio(_audio('second'));
    theme.applyThemeMode(ThemeMode.dark);
    final currentScheme = theme.currScheme;
    for (final entry in oldPalettes.entries) {
      entry.value.complete(ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: entry.key,
      ));
    }
    await stale;
    expect(theme.currScheme, currentScheme);
    expect((theme.backdropImage! as ResizeImage).imageProvider, _secondImage);
  });

  test('disabling clears immediately and enabling reloads the current song',
      () async {
    var enabled = true;
    var loads = 0;
    final theme = ThemeProvider.forTesting(
      seedColor: _fallback,
      dynamicThemeEnabled: () => enabled,
      loadArtwork: (_) async {
        loads++;
        return _firstImage;
      },
      extractScheme: _extract,
    );
    addTearDown(theme.dispose);
    final audio = _audio('first');
    await theme.applyThemeFromAudio(audio);
    enabled = false;
    theme.syncDynamicThemeSetting();
    _expectDefault(theme);
    await theme.applyThemeFromAudio(audio);
    expect(loads, 1);
    enabled = true;
    theme.syncDynamicThemeSetting();
    await theme.applyThemeFromAudio(audio);
    expect(loads, 2);
    expect(theme.backdropImage, isNotNull);
  });

  test('disabling while loading invalidates the pending result', () async {
    var enabled = true;
    final image = Completer<ImageProvider?>();
    final theme = ThemeProvider.forTesting(
      seedColor: _fallback,
      dynamicThemeEnabled: () => enabled,
      loadArtwork: (_) => image.future,
      extractScheme: _extract,
    );
    addTearDown(theme.dispose);
    final pending = theme.applyThemeFromAudio(_audio('first'));
    enabled = false;
    theme.syncDynamicThemeSetting();
    image.complete(_firstImage);
    await pending;
    _expectDefault(theme);
  });

  test('initially disabled theme tracks songs without loading images',
      () async {
    var enabled = false;
    final loadedIds = <String?>[];
    final theme = ThemeProvider.forTesting(
      seedColor: _fallback,
      dynamicThemeEnabled: () => enabled,
      loadArtwork: (audio) async {
        loadedIds.add(audio.onlineId);
        return _secondImage;
      },
      extractScheme: _extract,
    );
    addTearDown(theme.dispose);
    await theme.applyThemeFromAudio(_audio('first'));
    final second = _audio('second');
    await theme.applyThemeFromAudio(second);
    expect(loadedIds, isEmpty);
    enabled = true;
    theme.syncDynamicThemeSetting();
    await theme.applyThemeFromAudio(second);
    expect(loadedIds, ['second']);
  });

  for (final failure in ['missing', 'load', 'decode']) {
    test('$failure artwork restores both fallback palettes', () async {
      final theme = ThemeProvider.forTesting(
        seedColor: _fallback,
        dynamicThemeEnabled: () => true,
        loadArtwork: (audio) async {
          if (audio.onlineId == 'first') return _firstImage;
          if (failure == 'load') throw StateError('unreadable artwork');
          return failure == 'missing' ? null : _secondImage;
        },
        extractScheme: (image, brightness) {
          if ((image as ResizeImage).imageProvider == _secondImage) {
            return Future.error(StateError('invalid image'));
          }
          return _extract(image, brightness);
        },
      );
      addTearDown(theme.dispose);
      await theme.applyThemeFromAudio(_audio('first'));
      expect(theme.backdropImage, isNotNull);
      await theme.applyThemeFromAudio(_audio('second'));
      _expectDefault(theme);
    });
  }

  test('choosing a seed prevents an old pending cover from replacing it',
      () async {
    final image = Completer<ImageProvider?>();
    final theme = ThemeProvider.forTesting(
      seedColor: _fallback,
      dynamicThemeEnabled: () => true,
      loadArtwork: (_) => image.future,
      extractScheme: _extract,
    );
    addTearDown(theme.dispose);
    final pending = theme.applyThemeFromAudio(_audio('first'));
    theme.applyTheme(seedColor: Colors.purple);
    image.complete(_firstImage);
    await pending;
    _expectDefault(theme, Colors.purple);
  });

  test('disposing rejects artwork that completes later', () async {
    final image = Completer<ImageProvider?>();
    var notifications = 0;
    final theme = ThemeProvider.forTesting(
      seedColor: _fallback,
      dynamicThemeEnabled: () => true,
      loadArtwork: (_) => image.future,
      extractScheme: _extract,
    );
    theme.addListener(() => notifications++);
    final pending = theme.applyThemeFromAudio(_audio('first'));
    theme.dispose();
    image.complete(_firstImage);
    await pending;
    expect(notifications, 0);
    expect(theme.backdropImage, isNull);
  });
}
