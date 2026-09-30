import 'dart:convert';
import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/component/tap_lyric_editor.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:dan_player/lyric/tap_lyric_session.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _audio = Audio('Song', 'Artist', 'Album', 0, 180, null, null,
    'background-fixture.mp3', 0, 0, null);

Widget _host(GlobalKey boundary, VoidCallback Function(BuildContext) open,
        {bool reduced = false}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal, brightness: Brightness.dark)),
      builder: (context, child) => RepaintBoundary(
        key: boundary,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: AppPresentationHost(child: child!),
        ),
      ),
      home: AppContentRegion(
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                  key: const ValueKey('open-editor'),
                  onPressed: open(context),
                  child: const Text('Open')),
            ),
          ),
        ),
      ),
    );

Future<int> _pixel(
    WidgetTester tester, GlobalKey boundary, Offset point, String name) async {
  return (await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final rgba =
          await image.toByteData(format: drawing.ImageByteFormat.rawRgba);
      final output = Platform.environment['DAN_EDITOR_BACKGROUND_RENDER_DIR'];
      if (output != null) {
        await Directory(output).create(recursive: true);
        final png = await image.toByteData(format: drawing.ImageByteFormat.png);
        await File('$output/$name.png').writeAsBytes(png!.buffer.asUint8List());
      }
      final index = (point.dy.round() * image.width + point.dx.round()) * 4;
      return rgba!.getUint32(index);
    } finally {
      image.dispose();
    }
  }))!;
}

// Optional native investigation: retain node identities and both child orders
// without changing semantics, frame policy or production widget structure.
Future<void> _traceSemantics(WidgetTester tester, String phase) async {
  final output = Platform.environment['DAN_EDITOR_SEMANTICS_TRACE_DIR'];
  if (output == null || output.isEmpty) return;
  debugPrintSynchronously('[editor-semantics] $phase');
  final views = <Map<String, Object?>>[];
  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    final nodes = <Map<String, Object?>>[];
    final traversalParents = <Object, int>{};
    final traversalChildren = <int, Object>{};
    String? identifier(Object? value) => value == null
        ? null
        : '${value.runtimeType}#${identityHashCode(value)}';
    void collect(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.traversalParentIdentifier case final Object value) {
        traversalParents[value] = node.id;
      }
      if (data.traversalChildIdentifier case final Object value) {
        traversalChildren[node.id] = value;
      }
      final paintChildren = <int>[];
      node.visitChildren((child) {
        paintChildren.add(child.id);
        return true;
      });
      nodes.add({
        'id': node.id,
        'parent': node.parent?.id,
        'paintChildren': paintChildren,
        'traversalChildren': node
            .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)
            .map((child) => child.id)
            .toList(),
        'label': data.label,
        'value': data.value,
        'tooltip': data.tooltip,
        'role': data.role.name,
        'identifier': data.identifier,
        'traversalParentIdentifier': identifier(data.traversalParentIdentifier),
        'traversalChildIdentifier': identifier(data.traversalChildIdentifier),
        'scopesRoute': data.flagsCollection.scopesRoute,
        'namesRoute': data.flagsCollection.namesRoute,
        'isHidden': data.flagsCollection.isHidden,
        'isSlider': data.flagsCollection.isSlider,
        'isButton': data.flagsCollection.isButton,
        'isEnabled': data.flagsCollection.isEnabled.name,
        'isMergedIntoParent': node.isMergedIntoParent,
        'mergeDescendants': node.mergeAllDescendantsIntoThisNode,
        'actions': data.actions,
        'rect': [
          data.rect.left,
          data.rect.top,
          data.rect.right,
          data.rect.bottom
        ],
      });
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    if (root != null) collect(root);
    for (final node in nodes) {
      final childIdentifier = traversalChildren[node['id']];
      if (childIdentifier != null) {
        node['matchingTraversalParent'] = traversalParents[childIdentifier];
      }
    }
    views.add({'viewId': view.flutterView.viewId, 'nodes': nodes});
  }
  await tester.runAsync(() async {
    await Directory(output).create(recursive: true);
    await File('$output/$phase.json').writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert({'phase': phase, 'views': views}));
  });
}

Future<void> _expectReachablePortalParents(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    await tester.pump();
    for (final view in tester.binding.renderViews) {
      final nodes = <SemanticsNode>[];
      void collect(SemanticsNode node) {
        nodes.add(node);
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null) collect(root);
      final parents = <Object>{};
      for (final node in nodes) {
        if (node.getSemanticsData().traversalParentIdentifier
            case final Object identifier) {
          parents.add(identifier);
        }
      }
      final missing = <String>[];
      for (final node in nodes) {
        final child = node.getSemanticsData().traversalChildIdentifier;
        if (child != null && !parents.contains(child)) {
          missing.add(
              'node ${node.id}: ${child.runtimeType}#${identityHashCode(child)}');
        }
      }
      expect(missing, isEmpty,
          reason:
              'Overlay portal children require reachable traversal parents');
    }
  } finally {
    handle.dispose();
  }
}

void main({String? onlyCase}) {
  void register(String name, WidgetTesterCallback callback) {
    if (onlyCase == null || onlyCase == name) testWidgets(name, callback);
  }

  register('editor method to format keeps the existing backdrop dimming',
      (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(
        boundary, (context) => () => showLyricEditorDialog(context, _audio)));
    await tester.tap(find.byKey(const ValueKey('open-editor')));
    await tester.pumpAndSettle();
    const point = Offset(5, 5);
    final initial = await _pixel(tester, boundary, point, 'method-settled');
    await tester.tap(find.byKey(const ValueKey('lyric-method-text')));
    final frames = <int>[];
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      frames.add(await _pixel(tester, boundary, point, 'method-format-$frame'));
    }
    expect(frames, everyElement(initial),
        reason: 'Choosing the next editor step must not fade two barriers');
    await tester.pumpAndSettle();
    expect(find.text('选择歌词编辑格式'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  register('timed tap save retains its backdrop through format and editing',
      (tester) async {
    await tester.runAsync(() => LyricDocumentStore.instance.load());
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(
        boundary, (context) => () => showLyricEditorDialog(context, _audio)));
    await _traceSemantics(tester, 'tap-save-00-player');
    await tester.tap(find.byKey(const ValueKey('open-editor')));
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'tap-save-01-method');
    await tester.tap(find.byKey(const ValueKey('lyric-method-tap')));
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'tap-save-02-text');
    final tap = find.byType(TapLyricEditor);
    final tapState = tester.state(tap);
    await tester.enterText(
        find.byKey(const ValueKey('tap-text')), 'Keep my text');
    await _traceSemantics(tester, 'tap-save-03-entered-text');
    final timed = Lrc.fromLrcText(
        '[00:01.00]First line\n[00:02.00]Second line', LrcSource.local)!;
    final canceled = tester.widget<TapLyricEditor>(tap).saveLyric(timed);
    await _traceSemantics(tester, 'tap-save-04-before-format');
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'tap-save-05-first-format');
    await tester.tap(find.text('取消'));
    await _traceSemantics(tester, 'tap-save-06-before-format-exit');
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'tap-save-07-format-canceled');
    expect(await canceled, isFalse);
    expect(tester.state(tap), same(tapState));
    // Exercise the real production save callback with completed timed output;
    // audio hardware and the tap recorder are independently covered elsewhere.
    final saved = tester.widget<TapLyricEditor>(tap).saveLyric(timed);
    await _traceSemantics(tester, 'tap-save-08-before-second-format');
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'tap-save-09-second-format');
    const point = Offset(5, 5);
    final initial = await _pixel(tester, boundary, point, 'tap-save-format');
    await tester.tap(find.byKey(const ValueKey('lyric-format-lrc')));
    await _traceSemantics(tester, 'tap-save-10-before-editor');
    final frames = <int>[];
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      await _traceSemantics(tester, 'tap-save-11-editor-frame-$frame');
      frames
          .add(await _pixel(tester, boundary, point, 'tap-save-editor-$frame'));
    }
    expect(frames, everyElement(initial));
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'tap-save-12-editor');
    await tester.tap(find.byKey(const ValueKey('lyric-editor-close')));
    await _traceSemantics(tester, 'tap-save-13-before-editor-exit');
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'tap-save-14-editor-canceled');
    expect(await saved, isFalse);
    expect(tester.state(tap), same(tapState));
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('tap-text')))
            .controller!
            .text,
        'Keep my text');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await _traceSemantics(tester, 'tap-save-15-unmounted');
    expect(tester.takeException(), isNull);
  });

  register('selection barriers remain cancellable and editing is protected',
      (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(
        boundary,
        (context) => () => showLyricEditorDialog(context, _audio,
            localLyricLoader: (_) async => '[00:01.00]First line')));
    Future<void> open() async {
      await tester.tap(find.byKey(const ValueKey('open-editor')));
      await tester.pumpAndSettle();
    }

    await open();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await open();
    await tester.tap(find.byKey(const ValueKey('lyric-method-text')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await open();
    await tester.tap(find.byKey(const ValueKey('lyric-method-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-format-lrc')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(LyricEditorDialog), findsOneWidget);
    final field = find.byKey(const ValueKey('lyric-editor-field'));
    await tester.enterText(field, '[00:01.00]Unsaved line');
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('放弃歌词修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text,
        '[00:01.00]Unsaved line');
    await tester.tap(find.byKey(const ValueKey('lyric-editor-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  register('abandoned editor workflow completes and unbinds its barrier',
      (tester) async {
    final boundary = GlobalKey();
    late Future<bool> result;
    await tester.pumpWidget(_host(
        boundary,
        (context) => () {
              result = showLyricEditorDialog(context, _audio);
            }));
    await tester.tap(find.byKey(const ValueKey('open-editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lyric-method-tap')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(await result, isFalse);
    expect(tester.takeException(), isNull);
  });

  register('editor opening and closing fade its backdrop once', (tester) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(
        boundary,
        (context) => () => showLyricEditorDialog(context, _audio,
            localLyricLoader: (_) async => '[00:01.00]First line')));
    await _traceSemantics(tester, 'entry-00-player');
    const point = Offset(5, 5);
    var previous = await _pixel(tester, boundary, point, 'entry-player');
    await tester.tap(find.byKey(const ValueKey('open-editor')));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      await _traceSemantics(tester, 'entry-01-method-frame-$frame');
      final current = await _pixel(tester, boundary, point, 'entry-$frame');
      expect(current, lessThanOrEqualTo(previous));
      previous = current;
    }
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'entry-02-method');
    final route =
        ModalRoute.of(tester.element(find.byType(LyricEditingMethodDialog)));
    await tester.tap(find.byKey(const ValueKey('lyric-method-text')));
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'entry-03-format');
    await tester.tap(find.byKey(const ValueKey('lyric-format-lrc')));
    await _traceSemantics(tester, 'entry-04-before-editor');
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'entry-05-editor');
    await _expectReachablePortalParents(tester);
    expect(ModalRoute.of(tester.element(find.byType(LyricEditorDialog))),
        same(route));
    expect(await _pixel(tester, boundary, point, 'entry-editing'), previous);
    await tester.tap(find.byKey(const ValueKey('lyric-editor-close')));
    await _traceSemantics(tester, 'entry-06-before-close');
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      await _traceSemantics(tester, 'entry-07-exit-frame-$frame');
      final current = await _pixel(tester, boundary, point, 'exit-$frame');
      expect(current, greaterThanOrEqualTo(previous));
      previous = current;
    }
    await tester.pumpAndSettle();
    await _traceSemantics(tester, 'entry-08-closed');
    expect(find.byType(Dialog), findsNothing);
    expect(previous, 0xffffffff);
    expect(tester.takeException(), isNull);
  });

  register('tap row changes keep their card opaque', (tester) async {
    tester.view.physicalSize = const Size(1120, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    final session = TapLyricSession()..text = 'First line\nSecond line';
    session.beginLines();
    session.mark(1);
    session.mark(2);
    final preview = LyricAudioPreview(_audio, mainPlayback: () => null);
    await tester.pumpWidget(_host(
        boundary,
        (context) => () => showAppDialog<void>(
            context: context,
            builder: (_) => TapLyricEditor(
                audio: _audio,
                preview: preview,
                initialSession: session,
                ensureTools: () async => true,
                fetchOnline: () async => null,
                saveLyric: (_) async => false))));
    await tester.tap(find.byKey(const ValueKey('open-editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tap-accept')));
    await tester.pump();
    final card = find.ancestor(
        of: find.byKey(const ValueKey('tap-current-original')),
        matching: find.byWidgetPredicate((widget) =>
            widget is Container && widget.decoration is BoxDecoration));
    final point = tester.getRect(card).topLeft + const Offset(5, 20);
    final scheme = Theme.of(tester.element(card)).colorScheme;
    final expected = (scheme.surfaceContainerLow.toARGB32() << 8 |
            scheme.surfaceContainerLow.toARGB32() >> 24) &
        0xffffffff;
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(await _pixel(tester, boundary, point, 'tap-row-$frame'), expected);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    register('editor tabs retain the painted dialog backdrop reduced=$reduced',
        (tester) async {
      tester.view.physicalSize = const Size(1120, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final preview = LyricAudioPreview(_audio, mainPlayback: () => null);
      await tester.pumpWidget(_host(
          boundary,
          (context) => () => showAppDialog<void>(
              context: context,
              builder: (_) => LyricEditorDialog(
                  audio: _audio,
                  preview: preview,
                  localLyricLoader: (_) async => '[00:01.00]A short line')),
          reduced: reduced));
      await tester.tap(find.byKey(const ValueKey('open-editor')));
      await tester.pumpAndSettle();
      final surface = find.byType(AppDialogContent);
      final originalRect = tester.getRect(surface);
      final point = originalRect.topLeft + const Offset(12, 35);
      final initial =
          await _pixel(tester, boundary, point, 'tabs-$reduced-original');
      for (final tab in [1, 2, 3, 0]) {
        final chip = find.byKey(ValueKey('lyric-editor-tab-$tab'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        final frames = <int>[];
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          frames.add(await _pixel(
              tester, boundary, point, 'tabs-$reduced-$tab-$frame'));
        }
        expect(tester.getRect(surface), originalRect,
            reason:
                'Tab content must not resize and expose the dialog backdrop');
        expect(frames, everyElement(initial));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('lyric-editor-close')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
