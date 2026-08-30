import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _icons = [Icons.list, Icons.grid_view, Icons.album];

List<AppSegmentOption<int>> _options() => [
      for (final (index, label) in [ui('列表'), ui('方形网格'), ui('圆形封面')].indexed)
        AppSegmentOption(
            value: index,
            label: label,
            icon: _icons[index],
            key: ValueKey('segment-label-$index')),
    ];

Widget _host(GlobalKey repaintKey,
        {required Brightness brightness,
        required double scale,
        Color seed = Colors.teal,
        int selected = 0,
        bool enabled = true,
        double minimumHeight = 0,
        ValueChanged<int>? onChanged}) =>
    MaterialApp(
      locale: uiLanguage.value.locale,
      supportedLocales: [
        for (final language in UiLanguage.values) language.locale
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeAnimationDuration: Duration.zero,
      theme: applyAppControlTheme(ThemeData(
        platform: TargetPlatform.windows,
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback,
        colorScheme:
            ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
      )),
      builder: (context, child) => UiLanguageScope(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: child!,
        ),
      ),
      home: Scaffold(body: Builder(builder: (context) {
        return Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: repaintKey,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: 1400, minHeight: minimumHeight),
                child: AppSegmentedControl<int>(
                  value: selected,
                  options: _options(),
                  onChanged: enabled ? onChanged ?? (_) {} : null,
                ),
              ),
            ),
          ),
        );
      })),
    );

Future<({Uint8List bytes, int width, int height})> _pixels(
    WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData())!;
      return (
        bytes: Uint8List.fromList(bytes.buffer.asUint8List()),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }))!;
}

Future<void> _expectPaintAndCenter(WidgetTester tester, GlobalKey repaintKey,
    {required int selected, required bool enabled}) async {
  final segmented = find.byType(SegmentedButton<int>);
  expect(segmented, findsOneWidget);
  final scheme = Theme.of(tester.element(segmented)).colorScheme;
  final boundary = tester.getRect(find.byKey(repaintKey));
  final outer = tester.getRect(segmented);
  final pixels = await _pixels(tester, repaintKey);
  final buttons =
      find.descendant(of: segmented, matching: find.byType(TextButton));
  expect(buttons, findsNWidgets(3));
  for (var index = 0; index < 3; index++) {
    final buttonRect = tester.getRect(buttons.at(index));
    final expected =
        enabled && index == selected ? scheme.primaryContainer : scheme.surface;
    final rgb = expected.toARGB32();
    // Sample the painted shape, not its hit-test/outer box. Keep clear of the
    // rounded corners, border and the glyphs in the middle of the segment.
    for (final y in [2, 3, pixels.height - 4, pixels.height - 3]) {
      for (final fraction in [.35, .5, .65]) {
        final x =
            (buttonRect.left - boundary.left + buttonRect.width * fraction)
                .floor();
        final offset = (y * pixels.width + x) * 4;
        for (var channel = 0; channel < 3; channel++) {
          final expectedChannel = (rgb >> (16 - channel * 8)) & 0xff;
          expect((pixels.bytes[offset + channel] - expectedChannel).abs(),
              lessThanOrEqualTo(1),
              reason: 'Segment $index must paint through both edges; '
                  'pixel ($x,$y), enabled=$enabled, selected=$selected');
        }
      }
    }

    expect(buttonRect.top, closeTo(outer.top, .01));
    expect(buttonRect.bottom, closeTo(outer.bottom, .01));
    expect(buttonRect.height, greaterThanOrEqualTo(44));
    final label = find.byKey(ValueKey('segment-label-$index'));
    final icon = find.descendant(
        of: buttons.at(index), matching: find.byIcon(_icons[index]));
    final labelRect = tester.getRect(label);
    final iconRect = tester.getRect(icon);
    final contents = labelRect.expandToInclude(iconRect);
    expect(contents.center.dx, closeTo(buttonRect.center.dx, .1));
    expect(contents.center.dy, closeTo(buttonRect.center.dy, .1));
    expect(labelRect.center.dy, closeTo(iconRect.center.dy, .1));
    final labelContext = tester.element(label);
    expect(DefaultTextStyle.of(labelContext).style.fontFamily,
        danEmbeddedFontFamily);
    expect(
        DefaultTextStyle.of(labelContext).style.color!.toARGB32(),
        (enabled
                ? index == selected
                    ? scheme.onPrimaryContainer
                    : scheme.primary
                : scheme.onSurface.withValues(alpha: .38))
            .toARGB32());
  }
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('segment pixels and centering $language $brightness $scale',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1800, 500);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          uiLanguage.value = language;
          final repaintKey = GlobalKey();
          for (final configuration in [
            (selected: 0, enabled: true, seed: Colors.teal, minimumHeight: 0.0),
            (
              selected: 2,
              enabled: true,
              seed: Colors.purple,
              minimumHeight: 72.0
            ),
            (
              selected: 2,
              enabled: false,
              seed: Colors.purple,
              minimumHeight: 72.0
            ),
          ]) {
            await tester.pumpWidget(_host(repaintKey,
                brightness: brightness,
                scale: scale,
                selected: configuration.selected,
                enabled: configuration.enabled,
                seed: configuration.seed,
                minimumHeight: configuration.minimumHeight));
            await tester.pumpAndSettle();
            await _expectPaintAndCenter(tester, repaintKey,
                selected: configuration.selected,
                enabled: configuration.enabled);
          }
        });
      }
    }
  }

  testWidgets('bottom of every visible segment belongs to the actual button',
      (tester) async {
    var selected = 0;
    final changes = <int>[];
    final repaintKey = GlobalKey();
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      return _host(repaintKey,
          brightness: Brightness.light,
          scale: 1,
          selected: selected,
          onChanged: (value) => setState(() {
                selected = value;
                changes.add(value);
              }));
    }));
    await tester.pumpAndSettle();
    for (final index in [1, 2, 0, 0]) {
      final segmented = find.byType(SegmentedButton<int>);
      final bounds = tester.getRect(segmented);
      final point = Offset(
          bounds.left + (index + .5) * bounds.width / 3, bounds.bottom - 2);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(selected, index);
    }
    expect(changes, [1, 2, 0]);
    expect(tester.takeException(), isNull);
  });
}
