import 'dart:async';

import 'package:desktop_lyric/appearance_palette_app.dart';
import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/palette_test_bridge.dart';

Map<String, Object?> snapshot(int session, {int revision = 1, int ack = 0}) => {
      'session': session,
      'revision': revision,
      'editAck': ack,
      'appearance': DesktopLyricAppearance.defaults.toJson(),
      'darkMode': session.isEven,
      'primary': session.isEven ? 0xffddb1ef : 0xff155f50,
      'surfaceContainer': session.isEven ? 0xff212121 : 0xfffafafa,
      'onSurface': session.isEven ? 0xffffffff : 0xff121212,
      'language': session.isEven ? 'en' : 'zh',
      'fontFamily': 'QAPaletteFont$session',
      'fontFamilyFallback': <String>['Segoe UI'],
      'saveError': null,
      'layoutError': null,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PaletteLoopbackChannel channel;
  late DesktopLyricPaletteClient client;
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    channel = PaletteLoopbackChannel('test/palette_reuse');
    channel.request = (call) async {
      calls.add(call);
      if (call.method == 'edit') {
        final args = call.arguments as Map;
        return snapshot(args['session'] as int,
            revision: (args['sequence'] as int) + 1,
            ack: args['sequence'] as int)
          ..['appearance'] = {
            ...DesktopLyricAppearance.defaults.toJson(),
            ...args['patch'] as Map,
          };
      }
      return null;
    };
    client = DesktopLyricPaletteClient(channel: channel);
  });
  tearDown(() {
    client.dispose();
    uiLanguage.value = UiLanguage.zh;
  });

  test('cold entry seeds exact snapshot without a ready round trip', () async {
    final bytes = const StandardMessageCodec().encodeMessage(snapshot(1))!;
    final hex = bytes.buffer
        .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final decoded = DesktopLyricPaletteClient.decodeStartupSnapshot([hex]);
    expect(decoded, snapshot(1));
    await client.initialize(initialSnapshot: decoded);
    expect(calls, isEmpty);
    expect(client.fontFamily, 'QAPaletteFont1');
  });

  test('malformed startup payloads fail without requesting owner state', () {
    for (final args in <List<String>>[
      [],
      [''],
      ['0'],
      ['zz'],
      ['00', '01'],
      ['0' * 65538]
    ]) {
      expect(() => DesktopLyricPaletteClient.decodeStartupSnapshot(args),
          throwsFormatException);
    }
    expect(calls, isEmpty);
  });

  test('20 warm sessions reset closing and edit sequence, no hidden edits',
      () async {
    await client.initialize(initialSnapshot: snapshot(1));
    for (var session = 1; session <= 20; session++) {
      if (session > 1) {
        expect(client.applySnapshot(snapshot(session), beginSession: true),
            isTrue);
      }
      expect(client.active, isTrue);
      expect(client.isDarkMode.value, session.isEven);
      expect(client.fontFamily, 'QAPaletteFont$session');
      client.appearance.setBackgroundOpacity(.71);
      await client.close(); // Flush -> ack -> close -> dormant.
      expect(client.active, isFalse);
      final edit = calls.lastWhere((c) => c.method == 'edit').arguments as Map;
      expect(edit['session'], session);
      expect(edit['sequence'], 1);
      final count = calls.length;
      client.appearance.setBackgroundOpacity(.2);
      await client.flush();
      await client.close();
      expect(calls.length, count);
    }
  });

  test('obsolete edit failure cannot poison a newly opened session', () async {
    final delayed = Completer<Object?>();
    channel.request = (call) => delayed.future;
    await client.initialize(initialSnapshot: snapshot(1));
    client.appearance.setBackgroundOpacity(.71);
    final flush = client.flush();
    client.suspend();
    expect(client.applySnapshot(snapshot(2), beginSession: true), isTrue);
    delayed.completeError(PlatformException(code: 'old_failure'));
    await flush;
    expect(client.saveError.value, isNull);
    expect(client.appearance.value, DesktopLyricAppearance.defaults);
    expect(client.active, isTrue);
  });

  test('obsolete successful edit cannot overwrite new session values',
      () async {
    final delayed = Completer<Object?>();
    channel.request = (call) => delayed.future;
    await client.initialize(initialSnapshot: snapshot(1));
    client.appearance.setBackgroundOpacity(.71);
    final flush = client.flush();
    client.suspend();
    expect(client.applySnapshot(snapshot(2), beginSession: true), isTrue);
    delayed.complete(snapshot(1, revision: 99, ack: 1));
    await flush;
    expect(client.isDarkMode.value, isTrue);
    expect(client.fontFamily, 'QAPaletteFont2');
    expect(client.saveError.value, isNull);
  });

  test('stale snapshots/suspend and invalid present cannot mutate active state',
      () async {
    await client.initialize(initialSnapshot: snapshot(2));
    expect(client.applySnapshot(snapshot(1), beginSession: true), isFalse);
    expect(
        client.applySnapshot(snapshot(3)..['primary'] = -1, beginSession: true),
        isFalse);
    await channel.receiver!(const MethodCall('suspend', 1));
    expect(client.active, isTrue);
    expect(client.fontFamily, 'QAPaletteFont2');
    await channel.receiver!(const MethodCall('suspend', 2));
    expect(client.active, isFalse);
  });

  testWidgets('same-session pre-show language refresh paints fully opaque',
      (tester) async {
    await client.initialize(initialSnapshot: snapshot(1));
    await tester.pumpWidget(DesktopLyricAppearanceApp(client: client));
    await tester.pumpAndSettle();
    final refresh = channel.receiver!(
        MethodCall('refresh', snapshot(1, revision: 2)..['language'] = 'en'));
    await tester.pump();
    await refresh;
    final panel = find.byKey(const ValueKey('desktop-appearance-dialog'));
    final fade = tester.widget<FadeTransition>(
        find.ancestor(of: panel, matching: find.byType(FadeTransition)).first);
    expect(fade.opacity.value, 1);
    expect(uiLanguage.value, UiLanguage.en);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden present has one forced fresh layout and rounded surface',
      (tester) async {
    await client.initialize(initialSnapshot: snapshot(1));
    await tester.pumpWidget(DesktopLyricAppearanceApp(client: client));
    await tester.pumpAndSettle();
    client.suspend();
    await tester.pump();
    final panel = find.byKey(const ValueKey('desktop-appearance-dialog'));
    expect(TickerMode.valuesOf(tester.element(panel)).enabled, isFalse);
    final clip = tester.widget<ClipRRect>(
        find.byKey(const ValueKey('desktop-appearance-rounded-surface')));
    expect(clip.borderRadius, BorderRadius.circular(16));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    var presented = false;
    final present = channel.receiver!(MethodCall('present', snapshot(2)))
        .then((_) => presented = true);
    await tester.pump();
    await present;
    expect(presented, isTrue);
    expect(TickerMode.valuesOf(tester.element(panel)).enabled, isTrue);
    expect(Theme.of(tester.element(panel)).colorScheme.primary.toARGB32(),
        0xffddb1ef);
    expect(uiLanguage.value, UiLanguage.en);
    expect(find.text(ui('歌词外观')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
