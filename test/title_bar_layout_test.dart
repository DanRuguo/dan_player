import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

const _titleKey = ValueKey('title-bar-layout-title');
const _capsuleKey = ValueKey('title-bar-layout-capsule');
const _songTextKey = ValueKey('title-bar-layout-song-text');
const _bodyKey = ValueKey('title-bar-layout-body');
const _bodyTextKey = ValueKey('title-bar-layout-body-text');
const _songText = '歌曲标题与完整歌词 · The complete song title and lyric · '
    '让文字随着音乐流动，较长的歌曲信息仍保留完整的辅助功能描述。'
    'A long song title remains available to accessibility and tooltip users.';

class _SongFixture extends StatelessWidget {
  const _SongFixture();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: _songText,
      child: DecoratedBox(
        key: _capsuleKey,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        // Match the live lyric view's padded, centred text. The content
        // slot avoids initializing playback or calling native audio APIs.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.center,
            child: Text(
              _songText,
              key: _songTextKey,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpTitleBar(
  WidgetTester tester, {
  required double width,
  required double dpi,
  required double textScale,
  bool settle = true,
  bool disableAnimations = false,
}) async {
  expect(PlayService.isInitialized, isFalse);
  tester.view.physicalSize = Size(width * dpi, 720 * dpi);
  tester.view.devicePixelRatio = dpi;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      platform: TargetPlatform.windows,
      useMaterial3: true,
      fontFamily: danEmbeddedFontFamily,
      fontFamilyFallback: danFontFamilyFallback,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF316D99)),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: const Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(48),
        child: TitleBar(key: _titleKey, songContent: _SongFixture()),
      ),
      // AppShell's desktop content now starts immediately below the title bar.
      // This marker checks the shared contract without loading native playback.
      body: ColoredBox(
        key: _bodyKey,
        color: Color(0xFFF2F2F2),
        child: Center(
          child: Text('Page text', key: _bodyTextKey),
        ),
      ),
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  expect(PlayService.isInitialized, isFalse);
  expect(tester.takeException(), isNull);
}

void _expectGeometry(
  WidgetTester tester, {
  required double width,
  required double dpi,
  required double textScale,
}) {
  final title = tester.getRect(find.byKey(_titleKey));
  final region = tester.getRect(find.byType(TitleBarSongRegion));
  final capsule = tester.getRect(find.byKey(_capsuleKey));
  final body = tester.getRect(find.byKey(_bodyKey));
  final controls = tester.getRect(find.byType(WindowControlls));
  final song = tester.renderObject<RenderParagraph>(find.byKey(_songTextKey));
  final expectedStartPadding = width < 1100 ? 16.0 : 0.0;

  expect(title.height, 48);
  expect(region.height, 48);
  expect(region.top, title.top);
  expect(capsule.height, 32);
  expect(capsule.top - title.top, 8);
  expect(title.bottom - capsule.bottom, 8);
  expect(body.top - capsule.bottom, 8);
  expect(capsule.center.dy, title.center.dy);
  expect(controls.center.dy, title.center.dy);
  expect(controls.height, lessThanOrEqualTo(48));
  expect(find.byTooltip('快捷键（F1）'), findsNothing);
  final minimize = tester.getRect(find.byTooltip('最小化'));
  final mini = tester.getRect(find.byTooltip('迷你播放器（Ctrl + M）'));
  final fullScreen = tester.getRect(find.byTooltip('全屏'));
  final maximize = tester.getRect(find.byTooltip('最大化'));
  final close = tester.getRect(find.byTooltip('退出'));
  final windowButtons = [minimize, mini, maximize, fullScreen, close];
  for (final button in windowButtons) {
    expect(button.size, minimize.size);
    expect(button.width, greaterThanOrEqualTo(40));
    expect(button.center.dy, title.center.dy);
  }
  for (var index = 1; index < windowButtons.length; index++) {
    expect(windowButtons[index].left - windowButtons[index - 1].right, 8);
  }
  expect(capsule.left - region.left, expectedStartPadding);
  expect(region.right - capsule.right, 16);
  expect(capsule.width, greaterThan(0));

  // 100%, 125%, 150% and 200% Windows display scaling all preserve equal
  // physical gaps: 8, 10, 12 and 16 pixels, with no version-specific correction.
  expect((capsule.top - title.top) * dpi, closeTo(8 * dpi, 0.001));
  expect((body.top - capsule.bottom) * dpi, closeTo(8 * dpi, 0.001));
  expect(song.size.height, lessThanOrEqualTo(capsule.height));
  expect(song.maxLines, 1);
  expect(song.softWrap, isFalse);
  expect(song.overflow, TextOverflow.ellipsis);

  final songScaler = MediaQuery.textScalerOf(
    tester.element(find.byKey(_songTextKey)),
  );
  final bodyScaler = MediaQuery.textScalerOf(
    tester.element(find.byKey(_bodyTextKey)),
  );
  expect(songScaler.scale(14), closeTo(14 * textScale.clamp(0, 1.5), 0.001));
  expect(bodyScaler.scale(14), closeTo(14 * textScale, 0.001));
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final windowCalls = <String>[];

  setUpAll(() async {
    // Real font metrics prevent Ahem from inventing title overflow that does
    // not occur in the shipped Windows UI.
    final loader = FontLoader(danEmbeddedFontFamily);
    loader.addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf'));
    await loader.load();
  });

  setUp(() {
    windowCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      windowCalls.add(call.method);
      if (call.method == 'isFullScreen' || call.method == 'isMaximized') {
        return false;
      }
      throw StateError('Unexpected native operation: ${call.method}');
    });
  });

  tearDown(() {
    expect(windowCalls, ['isFullScreen', 'isMaximized']);
    expect(PlayService.isInitialized, isFalse);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final width in [900.0, 1280.0]) {
    for (final dpi in [1.0, 1.25, 1.5, 2.0]) {
      for (final textScale in [1.0, 1.25, 1.5, 2.0]) {
        testWidgets(
          '${width < 1100 ? 'medium' : 'large'} title: DPI $dpi, text $textScale',
          (tester) async {
            await _pumpTitleBar(
              tester,
              width: width,
              dpi: dpi,
              textScale: textScale,
            );
            _expectGeometry(
              tester,
              width: width,
              dpi: dpi,
              textScale: textScale,
            );
          },
        );
      }
    }
  }

  for (final width in [641.0, 1099.0, 1100.0]) {
    testWidgets('title breakpoint $width keeps equal gaps with 200% text',
        (tester) async {
      await _pumpTitleBar(tester, width: width, dpi: 1.25, textScale: 2);
      _expectGeometry(tester, width: width, dpi: 1.25, textScale: 2);
    });
  }

  testWidgets('entrance leaves native drag and window-button targets fixed',
      (tester) async {
    await _pumpTitleBar(
      tester,
      width: 1280,
      dpi: 1.25,
      textScale: 1,
      settle: false,
    );
    final drag = find.byType(DragToMoveArea);
    final dragRect = tester.getRect(drag);
    final minimize = find.byTooltip('最小化');
    final minimizeRect = tester.getRect(minimize);
    final titleRect = tester.getRect(find.byKey(_titleKey));
    final songEntry = find.byWidgetPredicate(
      (widget) => widget is AppEntrance && widget.identity == 'title-song',
    );
    final opacity = find.descendant(
      of: songEntry,
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    // Content can rise, but the drag region and click targets must never move.
    expect(
      find.ancestor(of: drag, matching: find.byType(AppEntrance)),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<Opacity>(opacity).opacity, inExclusiveRange(0, 1));
    expect(tester.getRect(drag), dragRect);
    expect(tester.getRect(minimize), minimizeRect);
    expect(tester.getRect(find.byKey(_titleKey)), titleRect);
    await tester.pumpAndSettle();
    _expectGeometry(tester, width: 1280, dpi: 1.25, textScale: 1);
  });

  testWidgets('reduced motion presents the title capsule in its final position',
      (tester) async {
    await _pumpTitleBar(
      tester,
      width: 900,
      dpi: 2,
      textScale: 2,
      settle: false,
      disableAnimations: true,
    );
    _expectGeometry(tester, width: 900, dpi: 2, textScale: 2);
    for (final entrance in find.byType(AppEntrance).evaluate()) {
      final opacity = find.descendant(
        of: find.byWidget(entrance.widget),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(opacity).opacity, 1);
    }
  });

  testWidgets('compact song scaling preserves full semantics and tooltips',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpTitleBar(tester, width: 900, dpi: 1.5, textScale: 2);
      final label = tester
          .getSemantics(find.byKey(_songTextKey))
          .getSemanticsData()
          .label;
      expect(label, contains(_songText));
      expect(find.byTooltip(_songText), findsOneWidget);
      expect(find.byTooltip('最小化'), findsOneWidget);
      _expectGeometry(tester, width: 900, dpi: 1.5, textScale: 2);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('shortcut help has no standalone title-bar button',
      (tester) async {
    await _pumpTitleBar(tester, width: 900, dpi: 1.25, textScale: 1);
    expect(find.byTooltip('快捷键（F1）'), findsNothing);
    expect(find.byTooltip('迷你播放器（Ctrl + M）'), findsOneWidget);
    _expectGeometry(tester, width: 900, dpi: 1.25, textScale: 1);
  });

  testWidgets('mini tooltip follows the current custom binding',
      (tester) async {
    final previous = AppSettings.instance.shortcuts.value;
    addTearDown(() => AppSettings.instance.shortcuts.value = previous);
    await _pumpTitleBar(tester, width: 900, dpi: 1.25, textScale: 1);
    AppSettings.instance.shortcuts.value = previous.withBinding(
      PlayerCommand.toggleMini,
      ShortcutChord(
        LogicalKeyboardKey.keyB.keyId,
        control: true,
        alt: true,
      ),
    );
    await tester.pump();
    expect(find.byTooltip('迷你播放器（Ctrl + M）'), findsNothing);
    expect(find.byTooltip('迷你播放器（Ctrl + Alt + B）'), findsOneWidget);
  });

  testWidgets('size lock disables maximize but keeps mini and fullscreen',
      (tester) async {
    final previous = AppSettings.instance.experience.value;
    addTearDown(() => AppSettings.instance.experience.value = previous);
    AppSettings.instance.experience.value =
        previous.copyWith(windowSizeLocked: true);
    await _pumpTitleBar(tester, width: 900, dpi: 1.25, textScale: 1);

    final locked = find.byTooltip('窗口大小已锁定');
    expect(locked, findsOneWidget);
    final maximizeButton = find.byKey(const ValueKey('title-maximize-control'));
    expect(maximizeButton, findsOneWidget);
    final maximize = tester.widget<IconButton>(maximizeButton);
    expect(maximize.onPressed, isNull);
    final scheme = Theme.of(tester.element(locked)).colorScheme;
    expect(
      maximize.style!.foregroundColor!
          .resolve(<WidgetState>{WidgetState.disabled}),
      scheme.primary.withValues(alpha: .38),
    );
    final miniButton = find.byKey(const ValueKey('title-mini-control'));
    final fullscreenButton =
        find.byKey(const ValueKey('title-fullscreen-control'));
    expect(tester.widget<IconButton>(miniButton).onPressed, isNotNull);
    expect(tester.widget<IconButton>(fullscreenButton).onPressed, isNotNull);
  });
}
