import 'dart:io';

import 'package:dan_player/folder_note_preferences.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

const _retained = ValueKey('retained-folder-tooltip');
const _fresh = ValueKey('fresh-folder-tooltip');
const _longName = 'Complete music collection 音楽 모음집 0123456789';
const _shortPath = r'J:\q';
const _longPath = r'J:\display-only\Long music collection 音楽 모음집 0123456789';

/// Count the real tooltip measurement paragraphs, excluding the visible Text
/// widgets and the compact-width threshold. One paragraph style scales once.
class _MeasurementScaler extends TextScaler {
  const _MeasurementScaler(this.factor, this.count);
  final double factor;
  final List<int> count;

  @override
  double scale(double fontSize) {
    final stack = StackTrace.current.toString();
    if (stack.contains('_FolderTileTooltip') &&
        stack.contains('TextPainter._createParagraphStyle')) {
      count[0]++;
    }
    return factor * fontSize;
  }

  @override
  double get textScaleFactor => factor;
}

List<String> _descriptions(Key key, String folderPath) => find
    .descendant(of: find.byKey(key), matching: find.byType(Tooltip))
    .evaluate()
    .map((element) => (element.widget as Tooltip).message)
    .whereType<String>()
    .where((message) => message.contains(folderPath))
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() => uiLanguage.value = UiLanguage.zh);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final scenario in [
    (
      name: 'first label overflow',
      cache: false,
      title: _longName,
      folderPath: _longPath,
      paragraphs: 1
    ),
    (
      name: 'path overflow',
      cache: true,
      title: 'q',
      folderPath: _longPath,
      paragraphs: 2
    ),
    (
      name: 'all labels fit',
      cache: true,
      title: 'q',
      folderPath: _shortPath,
      paragraphs: 3
    ),
  ]) {
    testWidgets('folder tooltip ${scenario.name} reuses natural measurements',
        (tester) async {
      sizePlaylistFeature(tester, width: 700, height: 600);
      final notes = ValueNotifier(const FolderNotePreferences()
          .withNote(scenario.folderPath, scenario.title));
      addTearDown(notes.dispose);
      final count = [0];
      final scaler = _MeasurementScaler(1, count);
      Future<void> save(FolderNotePreferences _) async =>
          fail('Display-only measurement must not save notes');
      Widget host(double width) {
        Widget card(Key key, TextScaler textScaler) => MediaQuery(
            data:
                MediaQueryData(textScaler: textScaler, disableAnimations: true),
            child: SizedBox(
                width: width,
                child: scenario.cache
                    ? PlayerDataFolderTile(
                        key: key,
                        directory: Directory(scenario.folderPath),
                        notes: notes,
                        saveNotes: save)
                    : AudioFolderTile(
                        key: key,
                        audioFolder: AudioFolder([], scenario.folderPath, 0, 0),
                        treeRow: true,
                        notes: notes,
                        saveNotes: save)));
        return UiLanguageScope(
            child: playlistFeatureHost(Column(children: [
          card(_retained, scaler),
          KeyedSubtree(
              key: UniqueKey(), child: card(_fresh, TextScaler.noScaling)),
        ])));
      }

      final measurements = <int>[];
      for (final width in [300.0, 301.0, 299.0, 270.0, 280.0, 300.0]) {
        await tester.pumpWidget(host(width));
        await tester.pumpAndSettle();
        measurements.add(count.single);
        expect(_descriptions(_retained, scenario.folderPath),
            _descriptions(_fresh, scenario.folderPath),
            reason: 'Every retained width must match a freshly measured card');
        expect(tester.takeException(), isNull);
      }
      // This is an operation count, not a timing/GPU/real-window claim.
      debugPrint(
          'folder tooltip ${scenario.name}: paragraph totals $measurements');
      expect(measurements.first, scenario.paragraphs,
          reason: 'The counter must observe each cold natural paragraph');
      expect(count.single, scenario.paragraphs,
          reason: 'Six compact widths must shape each unchanged label once');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'folder tooltip measurements invalidate current content and fonts',
      (tester) async {
    sizePlaylistFeature(tester, width: 700, height: 600);
    final notes =
        ValueNotifier(const FolderNotePreferences().withNote(_shortPath, 'q'));
    addTearDown(notes.dispose);
    final count = [0];
    var scaler = _MeasurementScaler(1, count);
    var direction = TextDirection.ltr;
    var locale = const Locale('zh');
    var policy = AppFontPolicy.defaults();
    var bold = false;
    var letterSpacing = 0.0;
    var folderPath = _shortPath;
    var width = 300.0;
    Future<void> save(FolderNotePreferences _) async =>
        fail('Display-only measurement must not save notes');
    Widget host() {
      Widget card(Key key, TextScaler textScaler) => MediaQuery(
          data: MediaQueryData(
              textScaler: textScaler, boldText: bold, disableAnimations: true),
          child: SizedBox(
              width: width,
              child: PlayerDataFolderTile(
                  key: key,
                  directory: Directory(folderPath),
                  notes: notes,
                  saveNotes: save)));
      final theme = ThemeData(platform: TargetPlatform.windows);
      return UiLanguageScope(
          child: MaterialApp(
              themeAnimationDuration: Duration.zero,
              theme: theme.copyWith(
                  textTheme: theme.textTheme.copyWith(
                      bodyMedium: theme.textTheme.bodyMedium!
                          .copyWith(letterSpacing: letterSpacing))),
              locale: locale,
              supportedLocales: UiLanguage.values.map((value) => value.locale),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: AppFontScope(
                  policy: policy,
                  child: Directionality(
                      textDirection: direction,
                      child: Scaffold(
                          body: Column(children: [
                        card(_retained, scaler),
                        KeyedSubtree(
                            key: UniqueKey(),
                            child:
                                card(_fresh, TextScaler.linear(scaler.factor))),
                      ]))))));
    }

    Future<void> check() async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(_descriptions(_retained, folderPath),
          _descriptions(_fresh, folderPath));
      expect(tester.takeException(), isNull);
    }

    await check();
    expect(count.single, 3);
    expect(_descriptions(_retained, folderPath), isEmpty);
    width = 180;
    await check();
    expect(_descriptions(_retained, folderPath), hasLength(1));
    expect(count.single, 3,
        reason: 'A narrow overflow uses the same natural widths');
    width = 300;
    await check();
    expect(_descriptions(_retained, folderPath), isEmpty);
    expect(count.single, 3);
    notes.value = notes.value.withNote(_shortPath, _longName);
    await check();
    expect(count.single, 4);
    expect(_descriptions(_retained, folderPath), hasLength(1));
    for (final change in <VoidCallback>[
      () => folderPath = _longPath,
      () => notes.value = notes.value.withNote(_longPath, _longName),
      () => scaler = _MeasurementScaler(1.5, count),
      () => direction = TextDirection.rtl,
      () => locale = const Locale('ja'),
      () => policy = policy.withLanguage(UiLanguage.ja),
      () => bold = true,
      () => letterSpacing = 1.25,
      () => uiLanguage.value = UiLanguage.en,
    ]) {
      final before = count.single;
      change();
      await check();
      expect(count.single, greaterThan(before),
          reason: 'Changed text or shaping inputs must be remeasured');
      final measured = count.single;
      width += 1;
      await check();
      expect(count.single, measured,
          reason: 'The new current measurements remain reusable on resize');
    }
    // Wide cards do no measurement even when metadata changes there. Returning
    // to compact width must use the current label rather than the old cache.
    width = 680;
    final beforeWide = count.single;
    await check();
    notes.value = notes.value.withNote(folderPath, 'changed while wide');
    await check();
    expect(count.single, beforeWide);
    expect(_descriptions(_retained, folderPath), isEmpty);
    width = 300;
    await check();
    expect(count.single, greaterThan(beforeWide));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
