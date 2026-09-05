import 'package:dan_player/component/brand_logo.dart';
import 'package:dan_player/component/startup_splash.dart';
import 'package:dan_player/page/settings_page/about_brand.dart';
import 'package:dan_player/page/settings_page/create_issue.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  Widget child, {
  Brightness brightness = Brightness.light,
  bool reducedMotion = false,
  double textScale = 1,
}) =>
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: brightness,
        ).copyWith(
          surface: brightness == Brightness.dark
              ? const Color(0xFF171C20)
              : const Color(0xFFF6F8F2),
        ),
      ),
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child,
      ),
    );

double _opacity(WidgetTester tester, Key key) =>
    tester.widget<Opacity>(find.byKey(key)).opacity;

double _overlayOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find
        .ancestor(
          of: find.byKey(StartupSplash.surfaceKey),
          matching: find.byType(Opacity),
        )
        .first)
    .opacity;

Image _brandImage(WidgetTester tester, AppBrand brand) => tester.widget<Image>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is BrandLogo && widget.brand == brand,
        ),
        matching: find.byType(Image),
      ),
    );

class _FailingImageProvider extends ImageProvider<_FailingImageProvider> {
  const _FailingImageProvider();

  @override
  Future<_FailingImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImageProvider key,
    ImageDecoderCallback decode,
  ) =>
      OneFrameImageStreamCompleter(
        Future<ImageInfo>.error(StateError('Unavailable brand artwork')),
      );
}

void main() {
  testWidgets('two brands share a two-second clock with a soft handoff',
      (tester) async {
    await tester.pumpWidget(_host(const StartupSplash(child: Text('Ready'))));
    expect(_opacity(tester, StartupSplash.rceOpacityKey), 1);
    expect(_opacity(tester, StartupSplash.danRuguoOpacityKey), 0);

    await tester.pump(const Duration(milliseconds: 790));
    expect(_opacity(tester, StartupSplash.rceOpacityKey), closeTo(1, .001));
    await tester.pump(const Duration(milliseconds: 210));
    final rce = _opacity(tester, StartupSplash.rceOpacityKey);
    final danRuguo = _opacity(tester, StartupSplash.danRuguoOpacityKey);
    expect(rce, closeTo(.5, .04));
    expect(danRuguo, closeTo(.5, .04));
    expect(rce + danRuguo, closeTo(1, .001));
    expect(_overlayOpacity(tester), 1,
        reason: 'The shared background does not flash during the handoff');

    await tester.pump(const Duration(milliseconds: 210));
    expect(_opacity(tester, StartupSplash.rceOpacityKey), closeTo(0, .001));
    expect(
        _opacity(tester, StartupSplash.danRuguoOpacityKey), closeTo(1, .001));
    await tester.pump(const Duration(milliseconds: 490));
    expect(_overlayOpacity(tester), closeTo(1, .001));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_overlayOpacity(tester), allOf(greaterThan(0), lessThan(1)));
    await tester.pump(const Duration(milliseconds: 149));
    expect(find.byKey(StartupSplash.overlayKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
    expect(find.text('Ready'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps two static one-second brand presentations',
      (tester) async {
    await tester.pumpWidget(_host(
      const StartupSplash(child: Text('Ready')),
      reducedMotion: true,
    ));
    await tester.pump(const Duration(milliseconds: 999));
    expect(_opacity(tester, StartupSplash.rceOpacityKey), 1);
    expect(_opacity(tester, StartupSplash.danRuguoOpacityKey), 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_opacity(tester, StartupSplash.rceOpacityKey), 0);
    expect(_opacity(tester, StartupSplash.danRuguoOpacityKey), 1);
    await tester.pump(const Duration(milliseconds: 999));
    expect(_overlayOpacity(tester), 1);
    expect(find.byKey(StartupSplash.overlayKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
  });

  testWidgets('platform reduced motion snaps a handoff without shortening time',
      (tester) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_host(const StartupSplash(child: Text('Ready'))));
    await tester.pump(const Duration(milliseconds: 900));
    expect(_opacity(tester, StartupSplash.rceOpacityKey), lessThan(1));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    expect(_opacity(tester, StartupSplash.rceOpacityKey), 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacity(tester, StartupSplash.danRuguoOpacityKey), 1);
    await tester.pump(const Duration(milliseconds: 999));
    expect(find.byKey(StartupSplash.overlayKey), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
  });

  testWidgets('theme updates change both assets and the single shared surface',
      (tester) async {
    const splash = StartupSplash(child: Text('Ready'));
    await tester.pumpWidget(_host(splash));
    expect((_brandImage(tester, AppBrand.rce).image as AssetImage).assetName,
        BrandLogo.rceLightAsset);
    expect(
        (_brandImage(tester, AppBrand.danRuguo).image as AssetImage).assetName,
        BrandLogo.danRuguoLightAsset);
    expect(
      tester.widget<ColoredBox>(find.byKey(StartupSplash.surfaceKey)).color,
      const Color(0xFFF6F8F2),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpWidget(_host(splash, brightness: Brightness.dark));
    expect((_brandImage(tester, AppBrand.rce).image as AssetImage).assetName,
        BrandLogo.rceDarkAsset);
    expect(
        (_brandImage(tester, AppBrand.danRuguo).image as AssetImage).assetName,
        BrandLogo.danRuguoDarkAsset);
    expect(
      tester.widget<ColoredBox>(find.byKey(StartupSplash.surfaceKey)).color,
      const Color(0xFF171C20),
    );
    expect(_opacity(tester, StartupSplash.danRuguoOpacityKey), 1,
        reason: 'Rebuilding the theme must not replay the RCE stage');
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(StartupSplash.overlayKey), findsNothing);
  });

  testWidgets('the splash blocks hidden controls and exposes one brand label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      var taps = 0;
      await tester.pumpWidget(_host(StartupSplash(
        child: Center(
          child: FilledButton(
            onPressed: () => taps++,
            child: const Text('Hidden action'),
          ),
        ),
      )));
      // Query the active semantics tree, not render objects' cached semantics
      // nodes: ExcludeSemantics may leave a detached debug node on a render box.
      expect(find.semantics.byLabel('RCE'), findsOneWidget);
      expect(find.semantics.byLabel('DanRuguo'), findsNothing);
      expect(find.semantics.byLabel('Hidden action'), findsNothing);
      await tester.tapAt(tester.getCenter(find.text('Hidden action')));
      expect(taps, 0);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.semantics.byLabel('RCE'), findsNothing);
      expect(find.semantics.byLabel('DanRuguo'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.tap(find.text('Hidden action'));
      expect(taps, 1);
    } finally {
      semantics.dispose();
    }
  });

  for (final brand in AppBrand.values) {
    testWidgets('$brand missing artwork has a safe accessible text fallback',
        (tester) async {
      await tester.pumpWidget(_host(BrandLogo(
        brand: brand,
        width: 216,
        height: 132,
        imageProvider: const _FailingImageProvider(),
      )));
      await tester.pump();
      expect(find.text(brand == AppBrand.rce ? 'RCE' : 'DanRuguo'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1200.0]) {
      testWidgets('about RCE follows report row at $brightness / $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        // Read the real configuration so the regression detects accidental
        // removal or reordering of the About signature in SettingsPage.
        await tester.pumpWidget(_host(
          const SettingsPage(),
          brightness: brightness,
          reducedMotion: true,
        ));
        final sections = tester
            .widget<GroupedSettings>(find.byType(GroupedSettings))
            .sections;
        final about = sections.singleWhere((section) => section.id == 'about');
        final issueIndex =
            about.children.indexWhere((w) => w is CreateIssueTile);
        expect(about.children[issueIndex + 1], isA<AboutBrand>());
        await tester.pumpWidget(_host(
          Scaffold(body: GroupedSettings(sections: [about])),
          brightness: brightness,
          reducedMotion: true,
          textScale: 2,
        ));
        await tester.pumpAndSettle();
        final logo = find.byType(BrandLogo);
        final bounds = tester.getRect(logo);
        final issueBounds = tester.getRect(find.byType(CreateIssueTile));
        expect(bounds.top, greaterThan(issueBounds.bottom + 20));
        expect(bounds.width, inInclusiveRange(160, 216));
        expect(bounds.center.dx, closeTo(issueBounds.center.dx, 1));
        expect(
          (_brandImage(tester, AppBrand.rce).image as AssetImage).assetName,
          BrandLogo.assetFor(AppBrand.rce, brightness),
        );
        expect(
          find.descendant(
              of: find.byType(AboutBrand), matching: find.byType(Card)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AboutBrand),
            matching: find.byType(ColoredBox),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('small startup windows contain both brand bounds',
      (tester) async {
    tester.view.physicalSize = const Size(220, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(const StartupSplash(child: SizedBox())));
    for (final brand in find.byType(BrandLogo).evaluate()) {
      final bounds = tester.getRect(find.byWidget(brand.widget));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(220));
      expect(bounds.bottom, lessThanOrEqualTo(160));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
