import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

class _LayoutAudio extends CategoryTestAudio {
  _LayoutAudio({required super.online})
      : super('歌曲标题 / A longer song title',
            artist: '艺术家 Artist', album: '专辑 Album');

  int artworkRequests = 0;

  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) {
    artworkRequests++;
    return super.artworkForSize(size);
  }
}

Future<void> _show(
  WidgetTester tester,
  _LayoutAudio audio, {
  double width = 440,
  double dpr = 1,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  TextStyle? bodyStyle,
  AudioTileSelection? selection,
  VoidCallback? onAction,
}) async {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(width * dpr, 440 * dpr);
  final theme = ThemeData(
      useMaterial3: true,
      platform: TargetPlatform.windows,
      brightness: brightness);
  await tester.pumpWidget(MaterialApp(
    theme: bodyStyle == null
        ? theme
        : theme.copyWith(
            textTheme: theme.textTheme.copyWith(bodyMedium: bodyStyle)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: AudioTile(
            audioIndex: 0,
            playlist: [audio],
            selection: selection,
            action: SizedBox.square(
              dimension: 44,
              child: IconButton(
                key: const ValueKey('tile-layout-action'),
                onPressed: onAction ?? () {},
                icon: const Icon(Icons.more_vert),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void _expectContentInsideRow(WidgetTester tester, _LayoutAudio audio) {
  final row = tester.getRect(find.byType(AudioTile));
  final mainRow =
      tester.getRect(find.byKey(const ValueKey('audio-tile-main-row')));
  final cover = tester.getRect(find.byType(AudioArtwork));
  expect(cover.size, const Size.square(48));
  expect(cover.center.dy, closeTo(mainRow.center.dy, 0.01));
  for (final text in [
    audio.displayTitle,
    '${audio.artist} - ${audio.album}',
  ]) {
    final bounds = tester.getRect(find.text(text));
    expect(bounds.top, greaterThanOrEqualTo(row.top + 7.99));
    expect(bounds.bottom, lessThanOrEqualTo(row.bottom - 7.99));
    expect(bounds.width, greaterThan(0));
  }
  final action =
      tester.getRect(find.byKey(const ValueKey('tile-layout-action')));
  expect(action.center.dx, greaterThan(row.right - 54));
  expect(action.center.dy, closeTo(mainRow.center.dy, 0.01));
  expect(action.size, const Size.square(44));
  final duration = find.text('0:02:00');
  final durationBounds = tester.getRect(duration);
  expect(durationBounds.bottom, lessThanOrEqualTo(row.bottom - 7.99));
  expect(
      tester.renderObject<RenderParagraph>(duration).didExceedMaxLines, isFalse,
      reason: 'The narrow layout must keep the duration readable, not hide it');
  expect(tester.takeException(), isNull);
}

void main() {
  tearDown(() {
    expect(PlayService.isInitialized, isFalse,
        reason: 'Layout tests must not initialize native playback');
  });

  for (final brightness in Brightness.values) {
    testWidgets('ordinary song rows remain 64px in $brightness',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final online in [false, true]) {
        final audio = _LayoutAudio(online: online);
        for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
          await _show(tester, audio, dpr: dpr, brightness: brightness);
          expect(tester.getSize(find.byType(AudioTile)).height, 64,
              reason: 'The Ink border must not add another 2px to the row');
          _expectContentInsideRow(tester, audio);
        }
      }
    });

    testWidgets('200 percent song rows fit narrow windows in $brightness',
        (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final online in [false, true]) {
        final audio = _LayoutAudio(online: online);
        for (final width in [320.0, 440.0, 760.0]) {
          for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
            await _show(tester, audio,
                width: width, dpr: dpr, brightness: brightness, textScale: 2);
            expect(
                tester.getSize(find.byType(AudioTile)).height, greaterThan(64));
            _expectContentInsideRow(tester, audio);
          }
        }
      }
    });
  }

  testWidgets('custom font metrics determine the row height without clamping',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = _LayoutAudio(online: true);
    await _show(tester, audio,
        width: 680,
        textScale: 2,
        bodyStyle: const TextStyle(fontSize: 24, height: 1.8));
    final titleHeight = tester.getSize(find.text(audio.displayTitle)).height;
    final metadataHeight =
        tester.getSize(find.text('${audio.artist} - ${audio.album}')).height;
    expect(tester.getSize(find.byType(AudioTile)).height,
        closeTo(titleHeight + metadataHeight + 16, 0.01));
    _expectContentInsideRow(tester, audio);
  });

  testWidgets('growing a row preserves artwork, selection and right action',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final audio = _LayoutAudio(online: false);
    var toggles = 0;
    var actions = 0;
    final selection = AudioTileSelection(
        enabled: true,
        selected: false,
        onToggle: () => toggles++,
        onStart: () {});
    await _show(tester, audio, selection: selection, onAction: () => actions++);
    final artworkState = tester.state(find.byType(AudioArtwork));
    final requests = audio.artworkRequests;
    await _show(tester, audio,
        textScale: 2, selection: selection, onAction: () => actions++);
    expect(tester.state(find.byType(AudioArtwork)), same(artworkState));
    expect(audio.artworkRequests, requests);
    await tester.tap(find.text(audio.displayTitle));
    await tester.pumpAndSettle();
    expect(toggles, 1);
    await tester.tap(find.byKey(const ValueKey('tile-layout-action')));
    await tester.pumpAndSettle();
    expect(actions, 1);
    expect(toggles, 1,
        reason: 'The right action must not select or play the row');
    _expectContentInsideRow(tester, audio);
  });

  testWidgets('song actions use the root overlay above the mini player',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _show(tester, _LayoutAudio(online: false));
    final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
    expect(anchor.useRootOverlay, isTrue);
    expect(anchor.reservedPadding, const EdgeInsets.fromLTRB(8, 8, 8, 116));
  });
}
