import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/personal_library_dialog.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/music_category_fixtures.dart';

class _Personal extends PersonalLibrary {
  _Personal(super.file, this.data);
  final Map<String, PersonalTrack> data;
  var reads = 0, saves = 0;
  List<String> added = [], removed = [];
  @override
  Future<Map<String, PersonalTrack>> snapshot() async {
    reads++;
    return Map.unmodifiable(data);
  }

  @override
  Future<void> apply(Iterable<Audio> targets,
      {bool changeRating = false,
      int? rating,
      bool changeTags = false,
      List<String> addTags = const [],
      List<String> removeTags = const []}) async {
    saves++;
    added = List.of(addTags);
    removed = List.of(removeTags);
  }
}

Finder _bubble(String tag) =>
    find.byKey(ValueKey(('personal-tag-history', tag)));
Finder get _input => find.byKey(const ValueKey('personal-tag-input'));

Widget _host(_Personal store, Audio target,
    {UiLanguage language = UiLanguage.zh,
    double scale = 1,
    GlobalKey? boundary}) {
  final policy = AppFontPolicy.defaults(language: language);
  return UiLanguageScope(
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: language.locale,
          supportedLocales:
              UiLanguage.values.map((language) => language.locale),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: applyAppControlTheme(ThemeData(
              platform: TargetPlatform.windows,
              fontFamily: policy.uiFamily,
              fontFamilyFallback: policy.fallback,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
          builder: (context, child) => RepaintBoundary(
              key: boundary,
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: true),
                  child: AppFontScope(policy: policy, child: child!))),
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showAppDialog<void>(
                          context: context,
                          builder: (_) => PersonalTrackEditor(
                              targets: [target], store: store)),
                      child: const Text('Open editor'))))));
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.widgetWithText(OutlinedButton, ui('添加标签')));
  await tester.tap(find.widgetWithText(OutlinedButton, ui('添加标签')));
  await tester.pumpAndSettle();
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final directory = Platform.environment['DAN_PERSONAL_TAG_RENDER_DIR'];
  if (directory == null) return;
  expect(
      p.isWithin(p.normalize(p.absolute('..', 'tool', 'qa-local')),
          p.normalize(p.absolute(directory))),
      true);
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(p.join(directory, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late _Personal personal;
  late CategoryTestAudio a, b, c, target;
  late List<AudioFolder> oldFolders;
  late List<Audio> oldOnline;
  late UiLanguage oldLanguage;

  setUpAll(() async {
    await ensureAppFontsLoaded(AppFontPolicy.defaults());
    for (final font in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      )
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('personal-tag-history-');
    expect(
        p.isWithin(p.normalize(p.absolute('..', 'tool', 'qa-local')),
            fixture.absolute.path),
        true);
    await TrackIdentityRegistry.instance.initialize(directory: fixture);
    a = CategoryTestAudio('A', path: p.join(fixture.path, 'a.mp3'));
    b = CategoryTestAudio('B', path: p.join(fixture.path, 'b.mp3'));
    c = CategoryTestAudio('C', path: p.join(fixture.path, 'c.mp3'));
    target =
        CategoryTestAudio('Target', path: p.join(fixture.path, 'target.mp3'));
    final stale =
        CategoryTestAudio('Removed', path: p.join(fixture.path, 'gone.mp3'));
    personal = _Personal(File(p.join(fixture.path, 'unused.json')), {
      a.stableTrackId: const PersonalTrack(tags: [
        '夜',
        'Alpha',
        'Beta',
        'Gamma',
        'Delta',
        'Epsilon',
        'Zeta',
        'Eta',
        'Theta',
        'Iota',
        '夜'
      ]),
      b.stableTrackId: const PersonalTrack(tags: ['夜', 'Alpha']),
      c.stableTrackId: const PersonalTrack(tags: ['夜']),
      stale.stableTrackId: const PersonalTrack(tags: ['Removed']),
    });
    oldFolders = List.of(AudioLibrary.instance.folders);
    oldOnline = List.of(AudioLibrary.instance.onlineAudioCollection);
    oldLanguage = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    AudioLibrary.instance.folders = [
      AudioFolder(
          [a, b, c, target, CategoryTestAudio('Duplicate', path: a.path)],
          fixture.path,
          0,
          0)
    ];
    AudioLibrary.instance.onlineAudioCollection = [];
    AudioLibrary.instance.rebuildDerivedCollections();
  });
  tearDown(() async {
    AudioLibrary.instance.folders = oldFolders;
    AudioLibrary.instance.onlineAudioCollection = oldOnline;
    AudioLibrary.instance.rebuildDerivedCollections();
    uiLanguage.value = oldLanguage;
    await fixture.delete(recursive: true);
  });

  testWidgets('tag history ranks eight valid library tags and shows count only',
      (tester) async {
    await tester.pumpWidget(_host(personal, target));
    await _open(tester);
    final tags = tester
        .widgetList<Widget>(find.byWidgetPredicate((widget) =>
            widget.key is ValueKey<(String, String)> &&
            (widget.key! as ValueKey<(String, String)>).value.$1 ==
                'personal-tag-history'))
        .map((widget) => (widget.key! as ValueKey<(String, String)>).value.$2)
        .toList();
    expect(tags,
        ['夜', 'Alpha', 'Beta', 'Delta', 'Epsilon', 'Eta', 'Gamma', 'Iota']);
    expect(_bubble('Removed'), findsNothing);
    expect(_bubble('Theta'), findsNothing);
    await tester.tap(_bubble('夜'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final menu = find.byType(MenuItemButton);
    expect(menu, findsOneWidget);
    expect(find.descendant(of: menu, matching: find.text('3')), findsOneWidget);
    expect(
        find.descendant(of: menu, matching: find.byType(Icon)), findsNothing);
    expect(tester.widget<TextFormField>(_input).controller!.text, isEmpty);
    expect(personal.saves, 0);
    expect(personal.reads, 1,
        reason: 'Opening bubbles reuses the editor snapshot');
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary tag selection fills a draft until both confirmations',
      (tester) async {
    await tester.pumpWidget(_host(personal, target));
    await _open(tester);
    await tester.tap(_bubble('Alpha'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(_input).controller!.text, 'Alpha');
    expect(
        tester.widget<TextFormField>(_input).controller!.selection.baseOffset,
        5);
    expect(find.text('5/80'), findsOneWidget);
    expect(personal.saves, 0);
    await tester.tap(find.widgetWithText(FilledButton, ui('确定')));
    await tester.pumpAndSettle();
    expect(_input, findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(personal.saves, 0);
    await tester.tap(find.widgetWithText(FilledButton, ui('保存')));
    await tester.pumpAndSettle();
    expect(personal.saves, 1);
    expect(personal.added, ['Alpha']);
    expect(personal.removed, isEmpty);
  });

  testWidgets('touch count and keyboard activation preserve full tag input',
      (tester) async {
    await tester.pumpWidget(_host(personal, target));
    await _open(tester);
    await tester.longPress(_bubble('夜'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, '3'), findsOneWidget);
    expect(tester.widget<TextFormField>(_input).controller!.text, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final text =
        find.descendant(of: _bubble('Alpha'), matching: find.text('Alpha'));
    Focus.of(tester.element(text)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter,
        physicalKey: PhysicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(_input).controller!.text, 'Alpha');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(_input, findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(personal.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single character bubble is centered without delete emphasis',
      (tester) async {
    await tester.pumpWidget(_host(personal, target));
    await _open(tester);
    final button =
        find.descendant(of: _bubble('夜'), matching: find.byType(TextButton));
    final text = find.descendant(of: _bubble('夜'), matching: find.text('夜'));
    expect(
        tester.getCenter(text).dx, closeTo(tester.getCenter(button).dx, .01));
    expect(
        tester.getCenter(text).dy, closeTo(tester.getCenter(button).dy, .01));
    final style = tester.widget<TextButton>(button).style!;
    final scheme = Theme.of(tester.element(button)).colorScheme;
    expect(style.foregroundColor!.resolve({}), scheme.onSurfaceVariant);
    expect(style.backgroundColor!.resolve({}), scheme.surfaceContainerHighest);
    expect(style.shape!.resolve({}), isA<StadiumBorder>());
    expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long tag fills all eighty characters and updates its counter',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 860);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final tag = 'Long'.padRight(80, 'x');
    personal.data
      ..clear()
      ..[a.stableTrackId] = PersonalTrack(tags: [tag]);
    await tester.pumpWidget(_host(personal, target, scale: 2));
    await _open(tester);
    expect(_bubble(tag).hitTestable(), findsOneWidget);
    expect(tester.getRect(_bubble(tag)).right, lessThanOrEqualTo(360));
    expect(find.descendant(of: _bubble(tag), matching: find.byType(Tooltip)),
        findsOneWidget);
    await tester.tap(_bubble(tag));
    await tester.pumpAndSettle();
    final controller = tester.widget<TextFormField>(_input).controller!;
    expect(controller.text, tag);
    expect(controller.selection.baseOffset, 80);
    expect(find.text('80/80'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, ui('确定')));
    await tester.pumpAndSettle();
    expect(find.text(tag), findsOneWidget);
    expect(personal.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty history and editing an existing tag retain original actions',
      (tester) async {
    personal.data.clear();
    await tester.pumpWidget(_host(personal, target));
    await _open(tester);
    expect(
        find.byKey(const ValueKey('personal-tag-history-wrap')), findsNothing);
    await tester.enterText(_input, 'Manual');
    await tester.tap(find.widgetWithText(FilledButton, ui('确定')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Manual'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(_input).controller!.text, 'Manual');
    expect(
        find.byKey(const ValueKey('personal-tag-history-wrap')), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, ui('删除')));
    await tester.pumpAndSettle();
    expect(find.text('Manual'), findsNothing);
    expect(personal.saves, 0);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final width in [360.0, 1100.0]) {
      testWidgets('tag bubbles ${language.name} width=$width large text',
          (tester) async {
        uiLanguage.value = language;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 860);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final boundary = GlobalKey();
        await tester.pumpWidget(_host(personal, target,
            language: language, scale: 2, boundary: boundary));
        await _open(tester);
        for (final tag in [
          '夜',
          'Alpha',
          'Beta',
          'Delta',
          'Epsilon',
          'Eta',
          'Gamma',
          'Iota'
        ]) {
          await tester.ensureVisible(_bubble(tag));
          expect(_bubble(tag).hitTestable(), findsOneWidget);
          final bounds = tester.getRect(_bubble(tag));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(width));
        }
        await tester.ensureVisible(_input);
        await _capture(
            tester, boundary, '${language.name}-${width.toInt()}-2x');
        await tester.tap(_bubble('夜'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(_input).controller!.text, '夜');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
