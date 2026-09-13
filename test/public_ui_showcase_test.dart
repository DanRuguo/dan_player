import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/cover_caption_colors.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shell.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/compact_player.dart';
import 'package:dan_player/component/frosted_surface.dart';
import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/component/horizontal_lyric_view.dart';
import 'package:dan_player/component/now_playing_bar_controls.dart';
import 'package:dan_player/component/now_playing_bar_row.dart';
import 'package:dan_player/component/playlist_browser.dart';
import 'package:dan_player/component/playlist_song_picker.dart';
import 'package:dan_player/component/rectangle_progress_indicator.dart';
import 'package:dan_player/component/seven_tone_spectrum.dart';
import 'package:dan_player/component/side_nav.dart';
import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/page/audios_page.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:dan_player/page/folders_page.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/page/search_page/search_result_page.dart';
import 'package:dan_player/page/settings_page/desktop_lyric_settings.dart';
import 'package:dan_player/page/settings_page/page.dart';
import 'package:dan_player/page/settings_page/theme_picker_dialog.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/playlist_view.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../scripts/support/sfnt_font.dart';

// This fixture never loads settings/library files, launches playback, captures
// desktop pixels, downloads art, or reads audio. PNG export is explicit opt-in;
// ordinary tests only exercise the production widgets with in-memory inputs.
const _updateRenderDirectory =
    String.fromEnvironment('DAN_PLAYER_UPDATE_RENDER_DIR');
const _selectedPage = String.fromEnvironment('DAN_PLAYER_PUBLIC_UI_PAGE');
const _export = bool.fromEnvironment('DAN_PLAYER_EXPORT_PUBLIC_UI') ||
    _updateRenderDirectory != '';
const _seed = Color(0xFF287B84);
const _layout = UiLayoutPreferences(libraryRowLayout: LibraryRowLayout.columns);
const _titles = [
  '演示曲目 01 · 纸上星河',
  '演示曲目 02 · 光点练习',
  '演示曲目 03 · 蓝色折线',
  '演示曲目 04 · 几何花园',
  '演示曲目 05 · 云端草稿',
  '演示曲目 06 · 方格漫步',
  '演示曲目 07 · 晨光样本',
  '演示曲目 08 · 留白片段',
];

class _ShowcaseCase {
  const _ShowcaseCase(this.page, this.name, this.brightness, this.size);
  final String page;
  final String name;
  final Brightness brightness;
  final Size size;
}

final _showcaseCases = [
  for (final page in ['library', 'settings', 'playlists'])
    for (final brightness in Brightness.values)
      for (final size in [const Size(1366, 900), const Size(600, 900)])
        _ShowcaseCase(
            page,
            '$page-${brightness.name}-${size.width > 640 ? 'wide' : 'narrow'}',
            brightness,
            size),
  const _ShowcaseCase('tiles', 'feature-category-tiles-light', Brightness.light,
      Size(1366, 900)),
  const _ShowcaseCase(
      'tiles', 'feature-category-tiles-dark', Brightness.dark, Size(1366, 900)),
  const _ShowcaseCase('categories', 'feature-categories-light',
      Brightness.light, Size(1366, 900)),
  const _ShowcaseCase(
      'mini', 'feature-mini-lyrics-dark', Brightness.dark, Size(680, 400)),
  const _ShowcaseCase('desktop', 'feature-desktop-settings-light',
      Brightness.light, Size(1366, 1000)),
  const _ShowcaseCase('appearance', 'feature-lyric-appearance-dark',
      Brightness.dark, Size(1366, 900)),
  const _ShowcaseCase(
      'theme', 'feature-theme-picker-light', Brightness.light, Size(1366, 900)),
  const _ShowcaseCase(
      'search', 'feature-search-dark', Brightness.dark, Size(1366, 900)),
  const _ShowcaseCase(
      'folders', 'feature-folders-light', Brightness.light, Size(1366, 900)),
  const _ShowcaseCase('statistics', 'feature-statistics-light',
      Brightness.light, Size(1366, 900)),
  const _ShowcaseCase(
      'playerbar', 'feature-player-bar-dark', Brightness.dark, Size(1000, 360)),
  const _ShowcaseCase('songpicker', 'feature-change-selected-songs-light',
      Brightness.light, Size(1366, 900)),
  const _ShowcaseCase(
      'spectrum', 'feature-spectrum-dark', Brightness.dark, Size(1100, 500)),
];

class _DemoLyric extends Lyric {
  _DemoLyric()
      : super([
          _DemoLyricLine(
              '演示歌词：把色彩写进今天', 'Demo lyrics: paint a little color into today.'),
        ]);
}

class _DemoLyricLine extends SyncLyricLine {
  _DemoLyricLine(String text, String translation)
      : super(Duration.zero, const Duration(seconds: 20),
            [_DemoLyricWord(text)], translation);
}

class _DemoLyricWord extends SyncLyricWord {
  _DemoLyricWord(String text)
      : super(Duration.zero, const Duration(seconds: 20), text);
}

class _DemoAudio extends Audio {
  _DemoAudio(int index, this.demoCover, {bool tileDemo = false})
      : super(
          _titles[index % _titles.length],
          '虚构演奏组 ${String.fromCharCode(65 + (tileDemo ? index : index % 3))}',
          '虚构专辑 ${index % 3 + 1} · 色彩习作',
          index + 1,
          168 + index * 13,
          320,
          44100,
          'Z:\\公开演示\\曲目-${index + 1}.flac',
          0,
          0,
          'Fictional presentation fixture',
          composer: '虚构作曲组 ${index % 3 + 1}',
          albumArtist: '虚构演奏组 ${String.fromCharCode(65 + index % 3)}',
          language: 'zho',
        );

  final ImageProvider demoCover;
  @override
  String get displayTitle => title;
  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) =>
      SynchronousFuture(demoCover);
}

// Only the fictional album art is generated: geometric shapes, no input image.
// Everything surrounding it is rendered by production Flutter widgets.
Future<Uint8List> _coverBytes(int index) async {
  const palettes = [
    [Color(0xFF245B66), Color(0xFF79D1BE), Color(0xFFF4DCB0)],
    [Color(0xFF59456C), Color(0xFFD5A6A2), Color(0xFFF7DDAC)],
    [Color(0xFF426272), Color(0xFF9EBCCA), Color(0xFFE1CE9D)],
  ];
  final palette = palettes[index % palettes.length];
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 256, 256), Paint()..color = palette[0]);
  canvas.drawCircle(const Offset(190, 65), 91, Paint()..color = palette[1]);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
        const Rect.fromLTWH(26, 104, 134, 126), const Radius.circular(24)),
    Paint()..color = palette[2],
  );
  canvas.drawCircle(const Offset(94, 172), 43, Paint()..color = palette[0]);
  for (var i = 0; i < 4; i++) {
    canvas.drawLine(
        Offset(182 + i * 12, 145),
        Offset(182 + i * 12, 225),
        Paint()
          ..color = palette[1]
          ..strokeWidth = 3);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

const _sevenToneLevels = <double>[.36, .72, .5, .92, .64, .8, .44];
const _frequencyLevels = <double>[
  .18,
  .24,
  .33,
  .45,
  .58,
  .72,
  .84,
  .7,
  .55,
  .48,
  .64,
  .88,
  .96,
  .78,
  .59,
  .43,
  .52,
  .68,
  .82,
  .62,
  .49,
  .74,
  .9,
  .67,
  .46,
  .38,
  .56,
  .76,
  .86,
  .69,
  .5,
  .42,
  .61,
  .79,
  .71,
  .53,
  .39,
  .57,
  .73,
  .63,
  .47,
  .35,
  .51,
  .66,
  .54,
  .4,
  .29,
  .2,
];

PlaybackStatistics _demoPlaybackStatistics() {
  final hours = <int>[
    0,
    0,
    0,
    0,
    0,
    0,
    const Duration(minutes: 12).inMilliseconds,
    const Duration(minutes: 28).inMilliseconds,
    const Duration(minutes: 20).inMilliseconds,
    const Duration(minutes: 8).inMilliseconds,
    0,
    0,
    const Duration(minutes: 16).inMilliseconds,
    const Duration(minutes: 34).inMilliseconds,
    const Duration(minutes: 42).inMilliseconds,
    const Duration(minutes: 25).inMilliseconds,
    const Duration(minutes: 18).inMilliseconds,
    const Duration(minutes: 30).inMilliseconds,
    const Duration(minutes: 54).inMilliseconds,
    const Duration(hours: 1, minutes: 8).inMilliseconds,
    const Duration(minutes: 47).inMilliseconds,
    const Duration(minutes: 31).inMilliseconds,
    const Duration(minutes: 14).inMilliseconds,
    0,
  ];
  return PlaybackStatistics.inMemory(initialData: {
    'version': 1,
    'tracks': [
      TrackPlaybackStatistics(
        id: 'demo:public-ui:track-1',
        title: _titles[0],
        artist: '虚构演奏组 A',
        album: '虚构专辑 1 · 色彩习作',
        online: false,
        playCount: 18,
        completedCount: 14,
        skippedCount: 1,
        listenMilliseconds:
            const Duration(hours: 3, minutes: 26).inMilliseconds,
      ).toMap(),
      TrackPlaybackStatistics(
        id: 'demo:public-ui:track-2',
        title: _titles[1],
        artist: '虚构演奏组 B',
        album: '虚构专辑 2 · 色彩习作',
        online: false,
        playCount: 13,
        completedCount: 10,
        skippedCount: 2,
        listenMilliseconds: const Duration(hours: 2, minutes: 8).inMilliseconds,
      ).toMap(),
      TrackPlaybackStatistics(
        id: 'demo:public-ui:track-3',
        title: _titles[2],
        artist: '虚构演奏组 C',
        album: '虚构专辑 3 · 色彩习作',
        online: false,
        playCount: 9,
        completedCount: 7,
        listenMilliseconds:
            const Duration(hours: 1, minutes: 32).inMilliseconds,
      ).toMap(),
    ],
    'days': {
      '2026-08-25': const Duration(hours: 1, minutes: 22).inMilliseconds,
      '2026-08-26': const Duration(minutes: 48).inMilliseconds,
      '2026-08-27': const Duration(hours: 2, minutes: 16).inMilliseconds,
      '2026-08-28': const Duration(hours: 1, minutes: 5).inMilliseconds,
      '2026-08-29': const Duration(minutes: 57).inMilliseconds,
      '2026-08-30': const Duration(minutes: 38).inMilliseconds,
    },
    'hours': hours,
  });
}

class _PlayerBarShowcase extends StatelessWidget {
  const _PlayerBarShowcase({required this.cover});

  final ImageProvider cover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppWindowSurface(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppContentRegion(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('正在播放',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface)),
                  const SizedBox(height: 6),
                  Text('可拖动进度 · 上一首 / 下一首 · 播放队列',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 840,
                    height: 92,
                    child: FrostedSurface(
                      blur: 22,
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            RectangleProgressIndicator(
                          size: constraints.biggest,
                          positionStream: const Stream<double>.empty(),
                          lengthProvider: () => 248,
                          initialPosition: 103,
                          trackIdentity: 'demo:public-ui:player-bar',
                          onSeek: (_) {},
                          child: NowPlayingBarRow(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox.square(
                                dimension: 62,
                                child: Image(image: cover, fit: BoxFit.cover),
                              ),
                            ),
                            title: _titles.first,
                            subtitle: '虚构演奏组 A · 虚构专辑 1 · 色彩习作',
                            identity: 'demo:public-ui:player-bar',
                            spectrum: MediaQuery(
                              data: MediaQuery.of(context)
                                  .copyWith(disableAnimations: false),
                              child: SevenToneSpectrum(
                                levels: _sevenToneLevels,
                                color: scheme.primary,
                                size: const Size(54, 22),
                              ),
                            ),
                            controlsBuilder: (showQueue) =>
                                NowPlayingBarControls(
                              isPlaying: true,
                              showQueue: showQueue,
                              onPrevious: () {},
                              onPlayPause: () {},
                              onNext: () {},
                              onQueue: () {},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpectrumShowcase extends StatefulWidget {
  const _SpectrumShowcase();

  @override
  State<_SpectrumShowcase> createState() => _SpectrumShowcaseState();
}

class _SpectrumShowcaseState extends State<_SpectrumShowcase> {
  final _levels = ValueNotifier<List<double>>(_frequencyLevels);

  @override
  void dispose() {
    _levels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppWindowSurface(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppContentRegion(
          child: Center(
            child: SizedBox(
              width: 920,
              child: FrostedSurface(
                blur: 22,
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('实时音乐频谱',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('${_titles[3]} · 固定虚构频谱帧',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(disableAnimations: false),
                          child: SevenToneSpectrum(
                            levels: _sevenToneLevels,
                            color: scheme.primary,
                            size: const Size(84, 34),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SpectrumProgressSection(
                      spectrum: SizedBox(
                        height: 190,
                        child: CustomPaint(
                          painter: FrequencySpectrumPainter(
                            levels: _levels,
                            startColor: scheme.primary,
                            endColor: scheme.tertiary,
                          ),
                        ),
                      ),
                      progress: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: .42,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Public presentation must never use the network.');
}

class _ShowcaseShell extends StatelessWidget {
  const _ShowcaseShell({required this.page, required this.preferences});
  final Widget page;
  final ValueNotifier<PlayerExperiencePreferences> preferences;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width <= 640;
    // Match AppShell's production chrome and content geometry, using its real
    // public components. Only native-dependent adapters (automatic updater and
    // live mini-player) are absent; this is documented, not a running-app shot.
    return AppWindowSurface(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TitleBar(
            songContent: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: HorizontalLyricContent(
                lyricFuture: null,
                positionStream: const Stream<double>.empty(),
                readPosition: () => 0,
              ),
            ),
          ),
        ),
        drawer: narrow ? const SideNav() : null,
        body: narrow
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: AppContentSurface(child: page),
              )
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ResizableSideNav(
                    preferences: preferences, persist: () async {}),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
                    child: AppContentSurface(child: page),
                  ),
                ),
              ]),
      ),
    );
  }
}

Future<void> _selectSettingsCategory(WidgetTester tester, String id) async {
  final picker = find.byKey(const ValueKey('settings-category-picker'));
  if (picker.evaluate().isNotEmpty) {
    await tester.tap(picker);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(ValueKey('settings-category-$id')).last);
  await tester.pumpAndSettle();
  if (id == 'appearance') expect(find.text('界面语言'), findsOneWidget);
}

Future<void> _exportImage(
    WidgetTester tester, GlobalKey key, String name, Size size) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    expect(image.width, size.width.toInt());
    expect(image.height, size.height.toInt());
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    expect(bytes.length, greaterThan(10000));
    final directory =
        _updateRenderDirectory.isEmpty ? 'docs/images' : _updateRenderDirectory;
    final destination = File('$directory/$name.png');
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes, flush: true);
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final covers = <ImageProvider>[];
  final iconFonts = <String, SfntFont>{};
  const channel = MethodChannel('window_manager');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late Directory profile;

  setUpAll(() async {
    final parent = await Directory('build/test-data').create(recursive: true);
    profile = await parent.createTemp('public-ui-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => profile.absolute.path);
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
      (
        'packages/material_symbols_icons/MaterialSymbolsRounded',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf'
      ),
      (
        'packages/material_symbols_icons/MaterialSymbolsSharp',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsSharp.ttf'
      ),
    ]) {
      final bytes = await rootBundle.load(font.$2);
      iconFonts[font.$1] = SfntFont.parse(bytes.buffer.asUint8List());
      final loader = FontLoader(font.$1)..addFont(Future.value(bytes));
      await loader.load();
    }
    // flutter_tester does not discover Windows system fallback fonts. Load the
    // exact family already named by production danFontFamilyFallback; do not
    // bundle/redistribute it, substitute the UI font, or install anything.
    final windowsDirectory = Platform.environment['WINDIR'];
    final koreanFont = windowsDirectory == null
        ? null
        : File('$windowsDirectory/Fonts/malgun.ttf');
    if (koreanFont != null && await koreanFont.exists()) {
      final bytes = await koreanFont.readAsBytes();
      final font = SfntFont.parse(bytes);
      expect('한국어'.runes.every(font.hasGlyph), isTrue);
      await (FontLoader('Malgun Gothic')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    } else if (_export) {
      fail('PNG export needs the existing Windows Malgun Gothic fallback. '
          'Run layout-only tests elsewhere; never publish blank language labels.');
    }
    for (var index = 0; index < 3; index++) {
      final provider = MemoryImage(await _coverBytes(index));
      covers.add(provider);
    }
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    final resolved = await profile.resolveSymbolicLinks();
    final parent = await Directory('build/test-data').resolveSymbolicLinks();
    if (!resolved.startsWith('$parent${Platform.pathSeparator}public-ui-')) {
      throw StateError('Refusing cleanup outside the public UI fixture');
    }
    await Directory(resolved).delete(recursive: true);
  });

  for (final scenario in _showcaseCases) {
    if (_selectedPage.isNotEmpty && scenario.page != _selectedPage) continue;
    final page = scenario.page;
    final brightness = scenario.brightness;
    final size = scenario.size;
    final name = scenario.name;
    testWidgets('public fictional production UI: $name', (tester) async {
      expect(PlayService.isInitialized, isFalse);
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = _NoNetwork();
      addTearDown(() => HttpOverrides.global = previousHttp);
      final nativeCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        nativeCalls.add(call.method);
        if (call.method == 'isMaximized' || call.method == 'isFullScreen') {
          return false;
        }
        throw StateError(
            'No native operation in public fixture: ${call.method}');
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final library = AudioLibrary.instance;
      final previousLibrary = library.audioCollection;
      final previousFolders = library.folders;
      final previousPref = AppPreference.instance.audiosPagePref;
      final previousCategory = AppPreference.instance.categoryPresentation;
      final previousFoldersPref = AppPreference.instance.foldersPagePref;
      final previousLanguage = uiLanguage.value;
      final previousLayout = AppSettings.instance.uiLayout.value;
      final previousTheme = AppSettings.instance.themeMode;
      final previousSeed = AppSettings.instance.defaultTheme;
      final previousAppearance =
          AppSettings.instance.desktopLyricAppearance.value;
      final previousExperience = AppSettings.instance.experience.value;
      final audios = [
        for (var index = 0;
            index < (page == 'tiles' ? 24 : _titles.length);
            index++)
          _DemoAudio(index, covers[index % 3], tileDemo: page == 'tiles'),
      ];
      if (page == 'tiles') {
        final groups = MusicCategories(audios).groups(MusicCategoryKind.artist);
        AppPreference.instance.categoryPresentation = CategoryPresentation(
            shape: CategoryCoverShape.rounded,
            showTitle: true,
            autoFill: true,
            sizes: {
              groups[1].persistenceKey: CategoryTileSize.large,
              groups[5].persistenceKey: CategoryTileSize.wide,
              groups[8].persistenceKey: CategoryTileSize.tall,
              groups[12].persistenceKey: CategoryTileSize.large,
            });
      }
      library.audioCollection = audios;
      library.folders = [
        AudioFolder(
            audios.take(3).toList(), r'Z:\公开演示\晨光收藏', 1787961600, 1787961600),
        AudioFolder(audios.skip(3).take(3).toList(), r'Z:\公开演示\色彩练习',
            1787788800, 1787788800),
        AudioFolder(
            audios.skip(6).toList(), r'Z:\公开演示\留白片段', 1787529600, 1787529600),
      ];
      AppPreference.instance.audiosPagePref =
          PagePreference(1, SortOrder.ascending, ContentView.list);
      AppPreference.instance.foldersPagePref =
          PagePreference(0, SortOrder.ascending, ContentView.list);
      uiLanguage.value = UiLanguage.zh;
      AppSettings.instance.uiLayout.value = _layout;
      AppSettings.instance.themeMode =
          brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark;
      AppSettings.instance.defaultTheme = _seed.toARGB32();
      if (page == 'appearance') {
        AppSettings.instance.desktopLyricAppearance.value =
            DesktopLyricAppearance.defaults.copyWith(
                lyricFontSize: 32,
                translationFontSize: 22,
                textOpacity: .85,
                backgroundOpacity: .2,
                strokeEnabled: true,
                followTheme: true);
      }
      if (page == 'desktop') {
        AppSettings.instance.experience.value = previousExperience.copyWith(
            closeToTray: true,
            taskbarControls: true,
            taskbarSongPreview: true,
            trayMenuBlurRadius: 12);
      }
      addTearDown(() {
        library.audioCollection = previousLibrary;
        library.folders = previousFolders;
        AppPreference.instance.audiosPagePref = previousPref;
        AppPreference.instance.categoryPresentation = previousCategory;
        AppPreference.instance.foldersPagePref = previousFoldersPref;
        uiLanguage.value = previousLanguage;
        AppSettings.instance.uiLayout.value = previousLayout;
        AppSettings.instance.themeMode = previousTheme;
        AppSettings.instance.defaultTheme = previousSeed;
        AppSettings.instance.desktopLyricAppearance.value = previousAppearance;
        AppSettings.instance.experience.value = previousExperience;
      });
      final tree = PlaylistTree([]);
      for (var index = 0; index < 3; index++) {
        tree.addAudios(tree.createPlaylist('演示歌单 ${index + 1} · 色彩练习'),
            audios.skip(index).take(4));
      }
      final preferences = ValueNotifier(const PlayerExperiencePreferences());
      final provider = ThemeProvider.forTesting(
        seedColor: _seed,
        themeMode: AppSettings.instance.themeMode,
        dynamicThemeEnabled: () => false,
        loadArtwork: (_) async => null,
        extractScheme: (_, value) async =>
            ColorScheme.fromSeed(seedColor: _seed, brightness: value),
      );
      final route = switch (page) {
        'library' => '/audios',
        'settings' || 'desktop' || 'appearance' || 'theme' => '/settings',
        'categories' || 'tiles' => '/categories',
        'folders' => '/folders',
        'statistics' => '/statistics',
        'search' => '/search/result',
        'mini' => '/mini',
        'playerbar' => '/player-bar',
        'spectrum' => '/spectrum',
        _ => '/playlists',
      };
      final demoLyric = SynchronousFuture<Lyric?>(_DemoLyric());
      final searchResult = UnionSearchResult('演示曲目')
        ..audios = audios.take(4).toList()
        ..online = SynchronousFuture(
            const OnlineSearchResponse(tracks: [], failures: {}));
      var classificationReads = 0;
      final classificationScanner = MusicClassificationScanner(
        readLyrics: (_) async {
          classificationReads++;
          return null;
        },
      );
      final playbackStatistics =
          page == 'statistics' ? _demoPlaybackStatistics() : null;
      if (playbackStatistics != null) {
        addTearDown(playbackStatistics.dispose);
      }
      var statisticsFileInspections = 0;
      var statisticsLyricReads = 0;
      final statisticsScanner = LibraryStatisticsScanner(
        windowsPaths: true,
        inspectFile: (path) async {
          statisticsFileInspections++;
          final index = audios.indexWhere((audio) => audio.path == path);
          return LocalAudioFileInfo.available(
            (index + 3) * 4 * 1024 * 1024,
            resolvedPath: path,
          );
        },
        readLyrics: (_) async {
          statisticsLyricReads++;
          return null;
        },
      );
      final router = GoRouter(initialLocation: route, routes: [
        GoRoute(
          path: route,
          builder: (context, _) => page == 'mini'
              ? Scaffold(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  body: AppContentRegion(
                      child: CompactPlayerView(
                    title: audios.first.displayTitle,
                    artist: audios.first.artist,
                    trackIdentity: audios.first.path,
                    cover: covers.first,
                    lyricFuture: demoLyric,
                    position: 6,
                    duration: audios.first.duration.toDouble(),
                    isPinned: true,
                    onPrevious: () {},
                    onPlayPause: () {},
                    onNext: () {},
                    onSeek: (_) {},
                    onRestore: () {},
                    onTogglePinned: () {},
                    onMinimize: () {},
                    onClose: () {},
                    onDragStart: () {},
                  )),
                )
              : page == 'playerbar'
                  ? _PlayerBarShowcase(cover: covers.first)
                  : page == 'spectrum'
                      ? const _SpectrumShowcase()
                      : _ShowcaseShell(
                          preferences: preferences,
                          page: switch (page) {
                            'library' => const AudiosPage(),
                            'settings' ||
                            'desktop' ||
                            'appearance' ||
                            'theme' =>
                              const SettingsPage(),
                            'categories' || 'tiles' => CategoriesPage(
                                audios: audios,
                                initialCategory: page == 'tiles'
                                    ? MusicCategoryKind.artist
                                    : MusicCategoryKind.bitrate,
                                classificationScanner: classificationScanner,
                                onOpenGroup: (_) {}),
                            'folders' => const FoldersPage(),
                            'statistics' => StatisticsPage(
                                scanner: statisticsScanner,
                                statistics: playbackStatistics!),
                            'search' =>
                              SearchResultPage(searchResult: searchResult),
                            _ => PlaylistBrowser(
                                tree: tree,
                                library: audios,
                                persist: () async {},
                                onPlay: (_, __) {},
                                onOpenAlbums: () {},
                                albumCount: 3,
                                initialView: PlaylistViewMode.circular,
                              ),
                          },
                        ),
        ),
      ]);
      final captureKey = GlobalKey();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          locale: UiLanguage.zh.locale,
          supportedLocales: [
            for (final value in UiLanguage.values) value.locale
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
            colorScheme:
                ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
          ),
          builder: (context, child) => RepaintBoundary(
            key: captureKey,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: UiLanguageScope(
                child: UiLayoutScope(
                  preferences: _layout,
                  child: AppPresentationHost(child: child!),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      if (page == 'tiles') {
        final artwork = find.descendant(
            of: find.byType(CategoriesPage), matching: find.byType(Image));
        bool captionsReady() =>
            artwork.evaluate().length == audios.length &&
            artwork.evaluate().every((element) {
              final image = element.widget as Image;
              final box = element.renderObject! as RenderBox;
              return CoverCaptionCache.cached(
                      image.image, box.size.width / box.size.height) !=
                  null;
            });
        // Pixel readback completes on the real image engine, outside fake time.
        // Wait for actual sampled colors, not for the five-second fallback.
        for (var attempt = 0; attempt < 40 && !captionsReady(); attempt++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(captionsReady(), isTrue,
            reason: 'Export actual sampled caption colors');
        await tester.pumpAndSettle();
      }
      Future<List<Audio>?>? songPickerResult;
      if (['settings', 'appearance', 'theme'].contains(page)) {
        await _selectSettingsCategory(tester, 'appearance');
      } else if (page == 'desktop') {
        await _selectSettingsCategory(tester, 'desktop');
      }
      if (page == 'appearance') {
        await Scrollable.ensureVisible(
            tester.element(find.byType(DesktopLyricSettings)),
            alignment: 0,
            duration: Duration.zero);
        await tester.pumpAndSettle();
      }
      if (page == 'theme') {
        // Open the real production selector, but never confirm a setting
        // or write to the user's configuration. Cancellation returns null.
        await Scrollable.ensureVisible(
            tester.element(find.byType(ThemeSelector)),
            alignment: .35,
            duration: Duration.zero);
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(
            of: find.byType(ThemeSelector),
            matching: find.byType(FilledButton)));
        await tester.pumpAndSettle();
        expect(find.byType(ThemePickerDialog), findsOneWidget);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }
      if (page == 'songpicker') {
        songPickerResult = showPlaylistSongPicker(
          tester.element(find.byType(PlaylistBrowser)),
          existingPaths: audios.take(3).map((audio) => audio.path).toSet(),
          library: audios,
          selectedAudios: audios.take(3).toList(),
          replaceSelection: true,
        );
        await tester.pumpAndSettle();
        expect(find.byType(PlaylistSongPicker), findsOneWidget);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }
      // Codec/GPU work runs outside fake widget time. pumpAndSettle alone
      // can finish before the first cold image decode; explicitly await
      // our allowlisted memory/asset images before capturing any frame.
      await tester.runAsync(() async {
        final context = captureKey.currentContext!;
        for (final image in covers) {
          await precacheImage(image, context);
        }
        await precacheImage(const AssetImage('app_icon.ico'), context);
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          expect(image.image, isNot(isA<FileImage>()));
          expect(image.image, isNot(isA<NetworkImage>()));
          await precacheImage(image.image, context);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          find.byType(TitleBar),
          {'mini', 'playerbar', 'spectrum'}.contains(page)
              ? findsNothing
              : findsOneWidget);
      for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
        final data = icon.icon;
        if (data == null) continue;
        final family = data.fontPackage == null
            ? data.fontFamily
            : 'packages/${data.fontPackage}/${data.fontFamily}';
        expect(iconFonts[family]?.hasGlyph(data.codePoint), isTrue,
            reason: 'Visible icon $family/${data.codePoint} must not be tofu.');
      }
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.image, isNot(isA<FileImage>()));
        expect(image.image, isNot(isA<NetworkImage>()));
      }
      for (final image in tester.widgetList<RawImage>(find.byType(RawImage))) {
        expect(image.image, isNotNull,
            reason: 'Never export a pending/empty cover or app icon.');
      }
      if (page == 'library') {
        expect(find.byType(AudiosPage), findsOneWidget);
        expect(find.byType(AudioTile), findsWidgets);
        expect(
            find.byKey(const ValueKey('music-search-action')), findsOneWidget);
        expect(find.text(_titles.first), findsOneWidget);
      } else if (page == 'playlists') {
        expect(find.byType(PlaylistBrowser), findsOneWidget);
        expect(find.text('演示歌单 1 · 色彩练习'), findsOneWidget);
      } else if (page == 'categories' || page == 'tiles') {
        expect(find.byType(CategoriesPage), findsOneWidget);
        if (page == 'categories')
          expect(find.text('257–320 kbps'), findsOneWidget);
        expect(classificationReads, 0,
            reason: 'Complete fictional tags must not request lyric files.');
      } else if (page == 'mini') {
        expect(find.byType(CompactPlayerView), findsOneWidget);
        expect(find.text('演示歌词：把色彩写进今天'), findsOneWidget);
        expect(find.text('Demo lyrics: paint a little color into today.'),
            findsOneWidget);
      } else if (page == 'search') {
        expect(find.byType(SearchResultPage), findsOneWidget);
        expect(find.byType(AudioTile), findsWidgets);
      } else if (page == 'folders') {
        expect(find.byType(FoldersPage), findsOneWidget);
        expect(find.byType(AudioFolderTile), findsNWidgets(3));
        expect(find.text('晨光收藏'), findsOneWidget);
      } else if (page == 'statistics') {
        expect(find.byType(StatisticsPage), findsOneWidget);
        expect(find.text('音乐统计'), findsOneWidget);
        expect(find.text('听歌行为'), findsOneWidget);
        expect(statisticsFileInspections, audios.length);
        expect(statisticsLyricReads, 0,
            reason: 'Complete fictional tags must not request lyric files.');
      } else if (page == 'playerbar') {
        expect(find.byType(NowPlayingBarRow), findsOneWidget);
        expect(find.byType(NowPlayingBarControls), findsOneWidget);
        expect(find.byType(RectangleProgressIndicator), findsOneWidget);
        expect(find.byType(SevenToneSpectrum), findsOneWidget);
        expect(
            tester
                .widget<SevenToneSpectrum>(find.byType(SevenToneSpectrum))
                .levels,
            _sevenToneLevels);
      } else if (page == 'songpicker') {
        expect(find.byType(PlaylistBrowser), findsOneWidget);
        expect(find.byType(PlaylistSongPicker), findsOneWidget);
        expect(find.text('更改所选歌曲'), findsOneWidget);
        expect(find.text('保存选择（3 首）'), findsOneWidget);
      } else if (page == 'spectrum') {
        expect(find.byType(SpectrumProgressSection), findsOneWidget);
        expect(find.byType(SevenToneSpectrum), findsOneWidget);
        expect(
            tester
                .widgetList<CustomPaint>(find.byType(CustomPaint))
                .any((paint) => paint.painter is FrequencySpectrumPainter),
            isTrue);
      } else if (page == 'desktop') {
        expect(find.byKey(const ValueKey('tray-menu-blur-radius-setting')),
            findsOneWidget);
      } else if (page == 'appearance') {
        expect(
            find.byKey(const ValueKey('desktop-text-opacity')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('desktop-lyric-stroke')), findsOneWidget);
      }
      if (_export) {
        await tester
            .runAsync(() => _exportImage(tester, captureKey, name, size));
      }
      if (page == 'theme') {
        await tester.tap(find.widgetWithText(TextButton, '取消'));
        await tester.pumpAndSettle();
        expect(find.byType(ThemePickerDialog), findsNothing);
      }
      if (page == 'songpicker') {
        await tester.tap(find.widgetWithText(TextButton, '取消').last);
        await tester.pumpAndSettle();
        expect(await songPickerResult, isNull);
        expect(find.byType(PlaylistSongPicker), findsNothing);
      }
      expect(PlayService.isInitialized, isFalse);
      expect(
          nativeCalls.every(
              (value) => value == 'isFullScreen' || value == 'isMaximized'),
          isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      provider.dispose();
      preferences.dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
