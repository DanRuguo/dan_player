import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_route_transition.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/vertical_lyric_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:desktop_lyric/app_edge_stretch.dart';

class _Lyrics extends Lyric {
  _Lyrics()
      : super([
          for (var i = 0; i < 12; i++)
            LrcLine(
                Duration(seconds: i * 20), '爱像首寂寞的歌 Morning $i┃Translation $i',
                length: const Duration(seconds: 20), isBlank: false)
              ..romanization = 'Ai xiang shou ji mo de ge',
        ]);
}

class _TimedWord extends SyncLyricWord {
  _TimedWord(int index)
      : super(Duration(seconds: index * 20), const Duration(seconds: 20),
            '爱像首寂寞的歌 Morning');
}

class _TimedLine extends SyncLyricLine {
  _TimedLine(int index)
      : super(Duration(seconds: index * 20), const Duration(seconds: 20),
            [_TimedWord(index)], 'Translation $index') {
    romanization = 'Ai xiang shou ji mo de ge';
  }
}

class _TimedLyrics extends Lyric {
  _TimedLyrics() : super([for (var i = 0; i < 12; i++) _TimedLine(i)]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native page and lyric endpoints retain ink and layout',
      (tester) async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    const output = String.fromEnvironment('DAN_ENDPOINT_RENDER');
    final boundary = GlobalKey();
    Future<List<double>> capture(String name, Rect rect,
        {bool red = false, bool vertical = false}) async {
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      try {
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        if (output.isNotEmpty) {
          await Directory(output).create(recursive: true);
          await File('$output/$name.png').writeAsBytes(
              (await image.toByteData(format: ui.ImageByteFormat.png))!
                  .buffer
                  .asUint8List());
        }
        double ink(int x, int y) => red
            ? (bytes[(y * image.width + x) * 4] -
                    bytes[(y * image.width + x) * 4 + 1])
                .clamp(0, 255)
                .toDouble()
            : 255.0 - bytes[(y * image.width + x) * 4];
        if (vertical) {
          return [
            for (var y = rect.top.ceil();
                y < math.min(image.height, rect.bottom.floor());
                y++)
              [
                for (var x = rect.left.ceil();
                    x < math.min(image.width, rect.right.floor());
                    x++)
                  ink(x, y)
              ].fold<double>(0, (sum, v) => sum + v),
          ];
        }
        return [
          for (var x = rect.left.ceil();
              x < math.min(image.width, rect.right.floor());
              x++)
            [
              for (var y = rect.top.ceil();
                  y < math.min(image.height, rect.bottom.floor());
                  y++)
                ink(x, y)
            ].fold<double>(0, (sum, v) => sum + v),
        ];
      } finally {
        image.dispose();
      }
    }

    Widget host(Widget child, {double scale = 1}) => RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                fontFamily: danEmbeddedFontFamily,
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.red)
                    .copyWith(
                        surface: Colors.white,
                        primary: Colors.red,
                        onSecondaryContainer: Colors.black)),
            home: Scaffold(
                backgroundColor: Colors.white,
                body: Transform.translate(
                    offset: const Offset(.35, .2),
                    child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topLeft,
                        child: Align(
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                                width: 680, height: 560, child: child)))))));

    final route = ValueNotifier<double>(.8);
    final animation = _ValueAnimation(route);
    const words = Padding(
        padding: EdgeInsets.only(left: 60.3, top: 90.2),
        child: Text('音乐 Music 分类 歌单 文件夹',
            style: TextStyle(fontSize: 24, color: Colors.black)));
    await tester.pumpWidget(host(const AppEntrance(child: words)));
    final entry = <List<double>>[];
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      entry
          .add(await capture('entry-$i', const Rect.fromLTWH(20, 70, 620, 80)));
    }
    final shifts = [
      for (final profile in entry.skip(2)) _shift(entry.last, profile).abs()
    ];
    debugPrint('Entrance registered shifts: $shifts');
    expect(shifts.reduce(math.max), lessThan(.05));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(AppRouteTransition(
        animation: animation,
        child: const AppEntrance(
            child: AppStretchEffect(
                axis: Axis.vertical, stretchStrength: 0, child: words)))));
    await tester.pumpAndSettle();
    final before =
        await capture('page-before', const Rect.fromLTWH(20, 70, 620, 80));
    route.value = 1;
    await tester.pump();
    final after =
        await capture('page-after', const Rect.fromLTWH(20, 70, 620, 80));
    final shift = _shift(before, after);
    debugPrint('Page terminal registered shift: $shift');
    expect(shift.abs(), lessThan(.05));
    await tester.pumpWidget(const SizedBox());
    route.dispose();

    final settings = LyricViewController();
    final lyric = _Lyrics();
    await tester.pumpWidget(host(ChangeNotifierProvider.value(
        value: settings,
        child: VerticalLyricScrollView(
            lyric: lyric,
            playing: false,
            positionStream: const Stream.empty(),
            readPosition: () => 85,
            onSeek: (_) {}))));
    await tester.pumpAndSettle();
    final current = find.byWidgetPredicate(
        (w) => w is LyricViewTile && identical(w.line, lyric.lines[4]));
    // A delayed final vsync must still use the final row geometry before paint.
    var lrcAction = 0;
    for (final change in <VoidCallback>[
      () => settings.setShowTimestamps(true),
      () => settings.setShowTimestamps(false),
      () => settings.setShowTranslation(false),
      () => settings.setShowTranslation(true),
      () => settings.setShowRomanization(false),
      () => settings.setShowRomanization(true),
    ]) {
      change();
      await tester.pump();
      final motions = tester
          .stateList<AnimatedWidgetBaseState<LyricLineMotion>>(
              find.byType(LyricLineMotion))
          .toList();
      final reveals = tester
          .stateList<AnimatedWidgetBaseState<LyricContentReveal>>(
              find.byType(LyricContentReveal))
          .toList();
      final primary = find.descendant(
          of: current,
          matching: find.byWidgetPredicate(
              (w) => w is BalancedLyricText && w.text.startsWith('爱像')));
      final primaryPaint = find.descendant(
          of: primary,
          matching: find.byWidgetPredicate((w) =>
              w is CustomPaint && w.painter is PlainLyricWordFollowPainter));
      final profiles = <List<double>>[];
      final localTops = <double>[];
      for (final t in [.8, .9, .95, .97, .98, .99, .999, 1.0]) {
        for (final motion in motions) {
          // ignore: invalid_use_of_protected_member
          motion.controller.stop();
          // ignore: invalid_use_of_protected_member
          motion.controller.value = t;
        }
        // The optional tracks own a separate clock. A forced line pose while
        // the reveal keeps running measures wall-time movement, not raster
        // drift at the requested animation fraction.
        for (final reveal in reveals) {
          // ignore: invalid_use_of_protected_member
          reveal.controller.stop();
          // ignore: invalid_use_of_protected_member
          reveal.controller.value = t;
        }
        await tester.pump();
        final rect = tester.getRect(primaryPaint.first);
        // The optional timestamp has its own reveal clock. Follow the actual
        // paragraph canvas instead of registering against a fixed page crop
        // that can include a newly visible red timestamp above the lyric.
        final bounds = Rect.fromLTWH(
            rect.left.floorToDouble() - 8,
            rect.top.floorToDouble() - 8,
            rect.width.ceilToDouble() + 16,
            rect.height.ceilToDouble() + 16);
        localTops.add(rect.top - bounds.top);
        profiles.add(await capture('lrc-$lrcAction-$t', bounds,
            red: true, vertical: true));
      }
      final residuals = [
        for (var i = 0; i < profiles.length; i++)
          _shift(profiles.last, profiles[i]) - (localTops[i] - localTops.last)
      ];
      for (final profile in profiles) {
        expect(profile.fold<double>(0, (sum, value) => sum + value),
            greaterThan(1000),
            reason: 'LRC registration requires visible primary ink');
      }
      for (final delta in [-1, 1]) {
        final shifted = List<double>.generate(
            profiles.last.length,
            (i) => i - delta >= 0 && i - delta < profiles.last.length
                ? profiles.last[i - delta]
                : 0);
        expect(_shift(profiles.last, shifted), closeTo(delta, .005));
      }
      debugPrint('LRC $lrcAction vertical raster residuals: $residuals');
      // The row moves during optional-track reveal, so fractional glyph
      // antialiasing can vary slightly. The last frames must return to the
      // same ink position after both animation clocks settle.
      expect(residuals.map((v) => v.abs()).reduce(math.max), lessThan(.35));
      expect(residuals.skip(4).map((v) => v.abs()).reduce(math.max),
          lessThan(.05));
      lrcAction++;
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 400));
      final scroll = tester
          .widget<CustomScrollView>(
              find.byKey(const ValueKey('vertical-lyric-scroll')))
          .controller!;
      final row = tester.getRect(current);
      expect(row.top + row.height * .34, closeTo(.2 + 560 * .34, .05));
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      expect(tester.takeException(), isNull);
    }
    expect(current, findsWidgets);
    await capture('lyrics-after', const Rect.fromLTWH(0, 0, 680, 560));
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
    final timedSettings = LyricViewController();
    final timedLyric = _TimedLyrics();
    final positions = StreamController<double>.broadcast(sync: true);
    var mediaPosition = 85.0;
    await tester.pumpWidget(host(ChangeNotifierProvider.value(
        value: timedSettings,
        child: VerticalLyricScrollView(
            lyric: timedLyric,
            playing: true,
            positionStream: positions.stream,
            readPosition: () => mediaPosition,
            onSeek: (_) {}))));
    await tester.pump(const Duration(milliseconds: 600));
    final timedCurrent = find.byWidgetPredicate(
        (w) => w is LyricViewTile && identical(w.line, timedLyric.lines[4]));
    var action = 0;
    for (final change in <VoidCallback>[
      () => timedSettings.setShowTimestamps(true),
      () => timedSettings.setShowTimestamps(false),
      () => timedSettings.setShowTranslation(false),
      () => timedSettings.setShowTranslation(true),
      () => timedSettings.setShowRomanization(false),
      () => timedSettings.setShowRomanization(true),
    ]) {
      change();
      await tester.pump();
      final motions = tester
          .stateList<AnimatedWidgetBaseState<LyricLineMotion>>(
              find.byType(LyricLineMotion))
          .toList();
      final reveals = tester
          .stateList<AnimatedWidgetBaseState<LyricContentReveal>>(
              find.byType(LyricContentReveal))
          .toList();
      final profiles = <List<double>>[];
      final verticalProfiles = <List<double>>[];
      final verticalLocalTops = <double>[];
      for (final t in [.8, .9, .95, .97, .98, .99, .999, 1.0]) {
        for (final motion in motions) {
          // Freeze the pose so native capture latency cannot skip the endpoint.
          // ignore: invalid_use_of_protected_member
          motion.controller.stop();
          // ignore: invalid_use_of_protected_member
          motion.controller.value = t;
        }
        for (final reveal in reveals) {
          // ignore: invalid_use_of_protected_member
          reveal.controller.stop();
          // ignore: invalid_use_of_protected_member
          reveal.controller.value = t;
        }
        positions.add(mediaPosition);
        await tester.pump();
        final row = tester.getRect(timedCurrent);
        expect(row.top + row.height * .34, closeTo(.2 + 560 * .34, .05));
        profiles.add(await capture(
            'playing-$action-$t', Rect.fromLTWH(0, row.top, 680, row.height),
            red: true));
        {
          final primary = find.descendant(
              of: timedCurrent,
              matching: find.byWidgetPredicate((w) =>
                  w is CustomPaint && w.painter is LyricWordHighlightPainter));
          final rect = tester.getRect(primary.first);
          final bounds = Rect.fromLTWH(
              rect.left.floorToDouble() - 8,
              rect.top.floorToDouble() - 8,
              rect.width.ceilToDouble() + 16,
              rect.height.ceilToDouble() + 16);
          verticalLocalTops.add(rect.top - bounds.top);
          verticalProfiles.add(await capture('playing-y-$action-$t', bounds,
              red: true, vertical: true));
        }
      }
      final terminalShift =
          _shift(profiles[profiles.length - 2], profiles.last).abs();
      debugPrint('Playing setting $action terminal shift: $terminalShift');
      expect(terminalShift, lessThan(.05));
      final verticalShift = _shift(
              verticalProfiles[verticalProfiles.length - 2],
              verticalProfiles.last)
          .abs();
      debugPrint(
          'Playing setting $action vertical terminal shift: $verticalShift');
      expect(verticalShift, lessThan(.05));
      final residuals = [
        for (var i = 0; i < verticalProfiles.length; i++)
          _shift(verticalProfiles.last, verticalProfiles[i]) -
              (verticalLocalTops[i] - verticalLocalTops.last)
      ];
      debugPrint(
          'Playing setting $action vertical raster residuals: $residuals');
      expect(residuals.map((v) => v.abs()).reduce(math.max), lessThan(.35));
      expect(residuals.skip(4).map((v) => v.abs()).reduce(math.max),
          lessThan(.05));
      mediaPosition += .016;
      action++;
    }
    for (final scale in [1.0, 1.25, 1.5]) {
      mediaPosition = 85.096;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(
          ChangeNotifierProvider.value(
              value: timedSettings,
              child: VerticalLyricScrollView(
                  lyric: timedLyric,
                  playing: true,
                  positionStream: positions.stream,
                  readPosition: () => mediaPosition,
                  onSeek: (_) {})),
          scale: scale));
      await tester.pump(const Duration(milliseconds: 600));
      var completionAction = 0;
      for (final change in <VoidCallback>[
        () => timedSettings.setShowTimestamps(true),
        () => timedSettings.setShowTimestamps(false),
        () => timedSettings.setShowTranslation(false),
        () => timedSettings.setShowTranslation(true),
        () => timedSettings.setShowRomanization(false),
        () => timedSettings.setShowRomanization(true),
      ]) {
        final primary = find.descendant(
            of: timedCurrent,
            matching: find.byWidgetPredicate((w) =>
                w is CustomPaint && w.painter is LyricWordHighlightPainter));
        final initialTop = tester.getRect(primary).top;
        change();
        await tester.pump();
        Map<String, Object> retainedInk() => {
              for (final paint in tester.widgetList<CustomPaint>(
                  find.descendant(
                      of: timedCurrent, matching: find.byType(CustomPaint))))
                if (paint.painter case final LyricWordHighlightPainter painter)
                  'primary': painter.layoutIdentity
                else if (paint.painter
                    case final PlainLyricWordFollowPainter painter)
                  painter.text.text!.toPlainText(): painter.text,
            };
        final motions = tester
            .stateList<AnimatedWidgetBaseState<LyricLineMotion>>(
                find.byType(LyricLineMotion))
            .toList();
        final reveals = tester
            .stateList<AnimatedWidgetBaseState<LyricContentReveal>>(
                find.byType(LyricContentReveal))
            .toList();
        for (final motion in motions) {
          // Keep the clock live through its natural completed status, rather
          // than only comparing two externally stopped controller values.
          // ignore: invalid_use_of_protected_member
          motion.controller.forward(from: .99);
        }
        for (final reveal in reveals) {
          // ignore: invalid_use_of_protected_member
          reveal.controller.forward(from: .99);
        }
        await tester.pump();
        final bounds = tester.getRect(primary).inflate(16);
        final profiles = <List<double>>[];
        final tops = <double>[];
        final inkBeforeCompletion = retainedInk();
        for (final elapsed in [0, 16, 16, 16, 64, 120]) {
          if (elapsed > 0) {
            await tester.pump(Duration(milliseconds: elapsed));
          }
          tops.add(tester.getRect(primary).top);
          profiles.add(await capture(
              'completed-$scale-$completionAction-${profiles.length}', bounds,
              red: true, vertical: true));
        }
        final residuals = [
          for (var i = 0; i < profiles.length; i++)
            _shift(profiles.last, profiles[i]) - (tops[i] - tops.last)
        ];
        final movement = tops.last - initialTop;
        debugPrint(
            'Setting direction $scale/$completionAction deltaY=$movement');
        if (completionAction == 0 || completionAction == 5) {
          expect(movement, greaterThan(0),
              reason: 'Showing content above moves the sung line down');
        } else if (completionAction == 1 || completionAction == 4) {
          expect(movement, lessThan(0));
        }
        for (final entry in retainedInk().entries) {
          expect(identical(entry.value, inkBeforeCompletion[entry.key]), isTrue,
              reason:
                  'Final-frame layout/cache must remain retained: ${entry.key}');
        }
        debugPrint(
            'Natural completion $scale/$completionAction residuals: $residuals');
        expect(residuals.map((value) => value.abs()).reduce(math.max),
            lessThan(.05));
        for (final motion in motions) {
          // ignore: invalid_use_of_protected_member
          expect(motion.controller.isAnimating, isFalse);
        }
        completionAction++;
      }
      mediaPosition = 105.0;
      positions.add(mediaPosition);
      await tester.pump();
      await tester.pump();
      final nextLine = find.byWidgetPredicate(
          (w) => w is LyricViewTile && identical(w.line, timedLyric.lines[5]));
      final nextPrimary = find.descendant(
          of: nextLine,
          matching: find.byWidgetPredicate((w) =>
              w is CustomPaint && w.painter is LyricWordHighlightPainter));
      final scroll = tester
          .widget<CustomScrollView>(
              find.byKey(const ValueKey('vertical-lyric-scroll')))
          .controller!;
      final target = tester.renderObject<RenderBox>(nextLine);
      scroll.jumpTo(RenderAbstractViewport.of(target)
          .getOffsetToReveal(target, .34)
          .offset
          .clamp(scroll.position.minScrollExtent,
              scroll.position.maxScrollExtent));
      final handoffX = <List<double>>[], handoffY = <List<double>>[];
      Rect? handoffBounds;
      for (final t in [.999, 1.0]) {
        final effects = tester
            .widgetList<LyricFollowEffects>(find.byType(LyricFollowEffects));
        for (final effect in effects) {
          if (effect.clock is AnimationController) {
            final clock = effect.clock as AnimationController;
            clock.stop();
            clock.value = t;
          }
        }
        for (final motion
            in tester.stateList<AnimatedWidgetBaseState<LyricLineMotion>>(
                find.byType(LyricLineMotion))) {
          // ignore: invalid_use_of_protected_member
          motion.controller.stop();
          // ignore: invalid_use_of_protected_member
          motion.controller.value = t;
        }
        await tester.pump();
        final rect = tester.getRect(nextPrimary);
        debugPrint(
            'Handoff t=$t top=${rect.top} left=${rect.left} width=${rect.width}');
        handoffBounds ??= tester.getRect(nextPrimary).inflate(16);
        handoffX.add(
            await capture('handoff-x-$scale-$t', handoffBounds, red: true));
        handoffY.add(await capture('handoff-y-$scale-$t', handoffBounds,
            red: true, vertical: true));
      }
      final handoffShiftX = _shift(handoffX.first, handoffX.last).abs();
      final handoffShiftY = _shift(handoffY.first, handoffY.last).abs();
      for (final profile in [...handoffX, ...handoffY]) {
        expect(profile.fold<double>(0, (sum, value) => sum + value),
            greaterThan(1000),
            reason: 'Registration requires visible highlight');
      }
      debugPrint(
          'Normal line handoff $scale terminal x=$handoffShiftX y=$handoffShiftY');
      expect(handoffShiftX, lessThan(.05));
      expect(handoffShiftY, lessThan(.05));
    }
    await tester.pumpWidget(const SizedBox());
    await positions.close();
    timedSettings.dispose();
  });
}

class _ValueAnimation extends Animation<double>
    with AnimationLocalStatusListenersMixin {
  _ValueAnimation(this.source);
  final ValueNotifier<double> source;
  @override
  double get value => source.value;
  @override
  AnimationStatus get status =>
      value == 1 ? AnimationStatus.completed : AnimationStatus.forward;
  @override
  void addListener(VoidCallback listener) => source.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => source.removeListener(listener);
  @override
  void didRegisterListener() {}
  @override
  void didUnregisterListener() {}
}

double _shift(List<double> reference, List<double> sample) {
  reference = [0, 0, 0, ...reference, 0, 0, 0];
  sample = [0, 0, 0, ...sample, 0, 0, 0];
  double correlation(int shift) {
    var result = 0.0;
    for (var i = 3; i < reference.length - 3; i++) {
      result += reference[i] * sample[i + shift];
    }
    return result;
  }

  var peak = 0;
  for (var i = -2; i <= 2; i++) {
    if (correlation(i) > correlation(peak)) peak = i;
  }
  final left = correlation(peak - 1),
      center = correlation(peak),
      right = correlation(peak + 1);
  return peak + .5 * (left - right) / (left - 2 * center + right);
}
