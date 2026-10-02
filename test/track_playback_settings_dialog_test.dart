import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/track_playback_settings_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/play_service/track_playback_settings.dart';
import 'package:desktop_lyric/l10n/catalog_track_playback.dart';
import 'package:desktop_lyric/l10n/ui_catalog.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

class _Library extends PersonalLibrary {
  // All methods used by the dialog are in-memory overrides, never file IO.
  _Library({this.saved}) : super(File('unused-track-settings-fixture.json'));
  TrackPlaybackSettings? saved;
  Completer<void>? holdSave;
  Completer<TrackPlaybackSettings?>? holdRead;
  Object? readError, writeError;
  int writes = 0;
  String? savedIdentity;
  @override
  Future<TrackPlaybackSettings?> playbackFor(String track) async {
    if (holdRead != null) return holdRead!.future;
    if (readError != null) throw readError!;
    return saved;
  }

  @override
  Future<void> setPlayback(Audio audio, TrackPlaybackSettings? settings) async {
    writes++;
    await holdSave?.future;
    if (writeError != null) throw writeError!;
    savedIdentity = audio.stableTrackId;
    saved = settings;
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  final audio = CategoryTestAudio('A 夜晚 🎶 긴 제목', online: true);
  const defaults = TrackPlaybackSettings(rate: 1, pitch: 0);
  const saved = TrackPlaybackSettings(rate: .875, pitch: -2.5);

  Future<void> mount(WidgetTester tester, _Library store,
      {Future<bool> Function(TrackPlaybackSettings?)? onSaved,
      GlobalKey? boundary,
      double width = 1000,
      double scale = 1}) async {
    sizePlaylistFeature(tester, width: width, height: 1000);
    final entry = Builder(
        builder: (context) => FilledButton(
            key: const ValueKey('open-track-settings'),
            onPressed: () => showAppDialog<void>(
                context: context,
                builder: (_) => TrackPlaybackSettingsDialog(
                    audio: audio,
                    defaults: defaults,
                    effective: defaults,
                    store: store,
                    onSaved: onSaved)),
            child: const Text('Open')));
    await tester.pumpWidget(boundary == null
        ? playlistFeatureHost(entry, textScale: scale)
        : listeningStatusHost(entry,
            scale: scale,
            boundary: boundary,
            brightness: width < 500 ? Brightness.dark : Brightness.light));
    await tester.tap(_key('open-track-settings'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(_key('track-settings-save'));
    await tester.tap(_key('track-settings-save'));
    await tester.pumpAndSettle();
  }

  test('new catalog has all translations and exact positional arguments', () {
    final arguments = RegExp(r'\{\d+\}');
    for (final entry in catalogTrackPlayback.entries) {
      expect(entry.value, hasLength(3), reason: entry.key);
      final source = arguments.allMatches(entry.key).map((m) => m[0]).toSet();
      for (var index = 0; index < 3; index++) {
        final text = entry.value[index];
        expect(text.trim(), isNotEmpty, reason: entry.key);
        expect(arguments.allMatches(text).map((m) => m[0]).toSet(), source,
            reason: entry.key);
        expect(uiCatalog[entry.key]![index], text);
        uiLanguage.value = UiLanguage.values[index + 1];
        expect(ui(entry.key), text);
      }
    }
  });

  testWidgets(
      'custom saved values round trip and changing draft leaves globals',
      (tester) async {
    final store = _Library(saved: saved);
    final global = AppSettings.instance.experience.value;
    await mount(tester, store);
    expect(
        find.descendant(of: _key('track-rate'), matching: find.text('0.88×')),
        findsOneWidget);
    expect(
        find.descendant(of: _key('track-pitch'), matching: find.text('-2.5')),
        findsOneWidget);
    await tester.tap(_key('track-rate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.25×').last);
    await tester.pumpAndSettle();
    expect(store.writes, 0);
    expect(AppSettings.instance.experience.value, same(global));
    await save(tester);
    expect(store.writes, 1);
    expect(store.savedIdentity, audio.stableTrackId);
    expect(store.saved!.toMap(), {'rate': 1.25, 'pitch': -2.5});
    expect(find.text(ui('已记住本曲设置，下次播放时生效')), findsOneWidget);
    expect(AppSettings.instance.experience.value, same(global));
  });

  testWidgets('clear only saves removal and reports live global restoration',
      (tester) async {
    final store = _Library(saved: saved);
    final applied = <TrackPlaybackSettings?>[];
    await mount(tester, store, onSaved: (value) async {
      applied.add(value);
      return true;
    });
    await tester.tap(_key('track-settings-clear'));
    await tester.pumpAndSettle();
    expect(store.saved, isNull);
    expect(applied, [null]);
    expect(find.text(ui('已清除本曲设置，当前播放已恢复全局默认')), findsOneWidget);
    expect(find.descendant(of: _key('track-rate'), matching: find.text('1×')),
        findsOneWidget);
    expect(find.descendant(of: _key('track-pitch'), matching: find.text('0')),
        findsOneWidget);
  });

  testWidgets('failed persistence does not claim save or call live apply',
      (tester) async {
    final store = _Library(saved: saved)..writeError = StateError('disk full');
    var applies = 0;
    await mount(tester, store, onSaved: (_) async {
      applies++;
      return true;
    });
    await save(tester);
    expect(store.saved, same(saved));
    expect(applies, 0);
    expect(find.textContaining('保存本曲设置失败'), findsOneWidget);
    expect(find.text(ui('已记住本曲设置，当前播放已应用')), findsNothing);
  });

  testWidgets('live failure reports committed profile honestly',
      (tester) async {
    final store = _Library();
    await mount(tester, store,
        onSaved: (_) async => throw StateError('native output'));
    await save(tester);
    expect(store.saved!.toMap(), defaults.toMap());
    expect(find.textContaining('设置已保存，但当前应用失败'), findsOneWidget);
    expect(find.textContaining('保存本曲设置失败'), findsNothing);
  });

  testWidgets('closing during commit retains saved track but cannot apply late',
      (tester) async {
    final store = _Library(saved: saved)..holdSave = Completer<void>();
    var applies = 0;
    await mount(tester, store, onSaved: (_) async {
      applies++;
      return true;
    });
    await tester.tap(_key('track-settings-save'));
    await tester.pump();
    expect(store.writes, 1);
    // The DialogRoute barrier can dismiss while the write is in flight.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(_key('track-playback-dialog'), findsNothing);
    store.holdSave!.complete();
    await tester.pumpAndSettle();
    expect(store.savedIdentity, audio.stableTrackId);
    expect(applies, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read failure disables overwrite until explicit retry succeeds',
      (tester) async {
    final store = _Library(saved: saved)
      ..readError = StateError('future version');
    await mount(tester, store);
    expect(tester.widget<FilledButton>(_key('track-settings-save')).onPressed,
        isNull);
    expect(find.textContaining('读取本曲设置失败'), findsOneWidget);
    store.readError = null;
    await tester.tap(find.text(ui('重试')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: _key('track-rate'), matching: find.text('0.88×')),
        findsOneWidget);
    expect(tester.widget<FilledButton>(_key('track-settings-save')).onPressed,
        isNotNull);
    expect(store.writes, 0);
  });

  testWidgets(
      'disabled-motion pending read stays idle and has no fake percentage',
      (tester) async {
    final store = _Library()..holdRead = Completer<TrackPlaybackSettings?>();
    await mount(tester, store);
    expect(_key('track-settings-loading-static'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.binding.hasScheduledFrame, isFalse);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(ui('正在读取本曲设置')), findsOneWidget);
    expect(tester.widget<FilledButton>(_key('track-settings-save')).onPressed,
        isNull);
    semantics.dispose();
    store.holdRead!.complete(saved);
    await tester.pumpAndSettle();
    expect(_key('track-settings-loading-static'), findsNothing);
    expect(tester.widget<FilledButton>(_key('track-settings-save')).onPressed,
        isNotNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          '${language.code} ${narrow ? 'narrow' : 'wide'} large-font track choices',
          (tester) async {
        uiLanguage.value = language;
        final boundary = GlobalKey();
        final prefix =
            'track-settings-${language.code}-${narrow ? 'narrow' : 'wide'}';
        await mount(tester, _Library(saved: saved),
            boundary: boundary, width: narrow ? 360 : 1080, scale: 2);
        expect(find.text(ui('本曲设置')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary, '$prefix-dialog');
        for (final choice in ['rate', 'pitch']) {
          await tester.ensureVisible(_key('track-$choice'));
          await tester.pumpAndSettle();
          await tester.tap(_key('track-$choice'));
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsWidgets);
          expect(tester.takeException(), isNull);
          await capturePlaylistFeature(tester, boundary, '$prefix-$choice');
          if (narrow) {
            final selected = choice == 'rate' ? .875 : -2.5;
            final selectedOption = _key('track-$choice-option-$selected');
            await tester.ensureVisible(selectedOption);
            await tester.pumpAndSettle();
            await tester.tap(selectedOption);
          } else {
            await tester.tap(find.text(ui('本曲设置')));
          }
          await tester.pumpAndSettle();
        }
        for (final action in ['track-settings-clear', 'track-settings-save']) {
          await tester.ensureVisible(_key(action));
          expect(tester.getRect(_key(action)).width, greaterThan(48));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
