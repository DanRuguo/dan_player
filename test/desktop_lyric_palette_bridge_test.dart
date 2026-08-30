import 'dart:async';

import 'package:desktop_lyric/appearance_palette_bridge.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/desktop_lyric_window_layout.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/desktop_lyric_test_support.dart';

const _hostChannel = MethodChannel('test/palette_host');
const _childChannel = MethodChannel('test/palette_child');
const _codec = StandardMethodCodec();
final _messenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Future<Object?> _native(
    MethodChannel channel, String method, Object? args) async {
  final response = Completer<Object?>();
  await _messenger.handlePlatformMessage(
      channel.name, _codec.encodeMethodCall(MethodCall(method, args)), (data) {
    try {
      response.complete(data == null ? null : _codec.decodeEnvelope(data));
    } catch (error, stack) {
      response.completeError(error, stack);
    }
  });
  return response.future;
}

class _Pair {
  final window = FakeDesktopLyricWindow();
  late final layout = DesktopLyricWindowLayout(adapter: window);
  final messages = <String>[];
  late final source = DesktopLyricController.detached(
      clock: PlaybackClock(automaticTicks: false), sendMessage: messages.add);
  late final host = DesktopLyricPaletteHost(
      controller: source,
      layout: layout,
      channel: _hostChannel,
      timeout: const Duration(milliseconds: 100));
  late final client = DesktopLyricPaletteClient(
      channel: _childChannel, timeout: const Duration(milliseconds: 100));
  final calls = <MethodCall>[];
  Map<Object?, Object?>? snapshot;
  Completer<Object?>? blockedEdit;
  Completer<Object?>? blockedUpdate;
  Completer<void>? blockedOpen;
  Object? openFailure;
  bool failEdit = false;
  Future<void>? opened;

  _Pair() {
    _messenger.setMockMethodCallHandler(_hostChannel, (call) async {
      calls.add(call);
      if (call.method == 'open') {
        if (openFailure != null) throw openFailure!;
        snapshot = Map<Object?, Object?>.from(call.arguments as Map);
        await blockedOpen?.future;
      }
      if (call.method == 'update') {
        final gate = blockedUpdate;
        if (gate != null) {
          blockedUpdate = null;
          return gate.future;
        }
        snapshot = Map<Object?, Object?>.from(call.arguments as Map);
        await _native(_childChannel, 'snapshot', call.arguments);
      }
      return null;
    });
    _messenger.setMockMethodCallHandler(_childChannel, (call) async {
      calls.add(call);
      if (call.method == 'ready') return snapshot;
      if (call.method == 'edit') {
        final gate = blockedEdit;
        if (gate != null) {
          blockedEdit = null;
          await gate.future;
        }
        if (failEdit) throw PlatformException(code: 'failed');
        return _native(_hostChannel, 'edit', call.arguments);
      }
      if (call.method == 'retry') {
        return _native(_hostChannel, 'retry', call.arguments);
      }
      if (call.method == 'close') {
        return _native(_hostChannel, 'closed', call.arguments);
      }
      return null;
    });
  }
  Future<void> open() async {
    opened = host.open();
    await Future<void>.delayed(Duration.zero);
    await client.initialize();
  }

  Future<void> end() async {
    await _native(_hostChannel, 'closed',
        {'session': snapshot!['session'], 'ownerHover': true});
    await opened;
  }

  void dispose() {
    host.dispose();
    client.dispose();
    source.dispose();
    layout.dispose();
    _messenger.setMockMethodCallHandler(_hostChannel, null);
    _messenger.setMockMethodCallHandler(_childChannel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Pair pair;
  setUp(() {
    uiLanguage.value = UiLanguage.zh;
    pair = _Pair();
  });
  tearDown(() {
    pair.dispose();
    uiLanguage.value = UiLanguage.zh;
  });

  test('same open is single flight; open/close never request owner geometry',
      () async {
    await pair.open();
    expect(identical(pair.host.open(), pair.opened), isTrue);
    expect(pair.host.isOpen.value, isTrue);
    expect(pair.layout.palettePresentation.value, isNotNull);
    expect(pair.calls.where((c) => c.method == 'open'), hasLength(1));
    await pair.end();
    expect(pair.window.operations, isEmpty);
    expect(pair.layout.palettePresentation.value, isNull);
    expect(pair.layout.paletteExitHover, isTrue);
  });

  test('100 slider edits coalesce and update the existing persisted model once',
      () async {
    await pair.open();
    for (var i = 0; i < 100; i++) {
      pair.client.appearance.setBackgroundOpacity(i / 100);
    }
    expect(pair.calls.where((c) => c.method == 'edit'), isEmpty);
    await pair.client.flush();
    expect(pair.calls.where((c) => c.method == 'edit'), hasLength(1));
    expect(pair.source.appearance.value.backgroundOpacity, .99);
    expect(pair.messages, hasLength(1));
    expect(
        pair.messages.single, contains('DesktopLyricAppearanceChangedMessage'));
    await pair.end();
  });

  test('in-flight slider patch preserves a newer unrelated owner edit',
      () async {
    await pair.open();
    final gate = pair.blockedEdit = Completer<Object?>();
    pair.client.appearance.setBackgroundOpacity(.4);
    final flush = pair.client.flush();
    await Future<void>.delayed(Duration.zero);
    pair.source.appearance
        .update(pair.source.appearance.value.copyWith(customColor: 0xff102030));
    await Future<void>.delayed(Duration.zero);
    expect(pair.client.appearance.value.backgroundOpacity, .4);
    pair.client.appearance.setBackgroundOpacity(.7);
    gate.complete(null);
    await flush;
    expect(pair.source.appearance.value.customColor, 0xff102030);
    expect(pair.source.appearance.value.backgroundOpacity, .7);
    expect(pair.client.appearance.value, pair.source.appearance.value);
    expect(pair.calls.where((c) => c.method == 'edit'), hasLength(2));
    await pair.end();
  });

  test('theme language errors and font snapshot stay live without echo edits',
      () async {
    await pair.open();
    pair.source.theme.value =
        const ThemeChangedMessage(0xff998877, 0xff223344, 0xffeeeeee);
    pair.source.isDarkMode.value = true;
    pair.source.appearanceSaveError.value = 'save fixture';
    pair.layout.lastError.value = 'layout fixture';
    uiLanguage.value = UiLanguage.ko;
    await Future<void>.delayed(Duration.zero);
    expect(pair.client.theme.value.primary, 0xff998877);
    expect(pair.client.isDarkMode.value, isTrue);
    expect(pair.client.saveError.value, 'save fixture');
    expect(pair.client.layoutError.value, 'layout fixture');
    expect(pair.snapshot!['language'], 'ko');
    expect(pair.client.fontFamily, 'DanPingFangSC');
    expect(pair.messages, isEmpty);
    await pair.end();
  });

  test('stale session edits and closed do not affect a reopened palette',
      () async {
    await pair.open();
    final oldSession = pair.snapshot!['session'];
    await pair.end();
    pair.opened = pair.host.open();
    await Future<void>.delayed(Duration.zero);
    await _native(_hostChannel, 'edit', {
      'session': oldSession,
      'sequence': 1,
      'patch': {'backgroundOpacity': .9}
    });
    await _native(_hostChannel, 'closed', {'session': oldSession});
    expect(pair.host.isOpen.value, isTrue);
    expect(pair.source.appearance.value.backgroundOpacity, 0);
    expect(pair.messages, isEmpty);
    await pair.end();
  });

  test('late failed update from previous session cannot close new session',
      () async {
    await pair.open();
    final gate = pair.blockedUpdate = Completer<Object?>();
    pair.source.isDarkMode.value = true;
    await Future<void>.delayed(Duration.zero);
    await pair.end();
    pair.opened = pair.host.open();
    await Future<void>.delayed(Duration.zero);
    gate.completeError(PlatformException(code: 'old_update_failed'));
    await Future<void>.delayed(Duration.zero);
    expect(pair.host.isOpen.value, isTrue);
    await pair.end();
  });

  test('creation failure is explicit and never invokes old resize fallback',
      () async {
    pair.openFailure = PlatformException(code: 'create_failed');
    await expectLater(pair.host.open(), throwsA(isA<PlatformException>()));
    expect(pair.host.isOpen.value, isFalse);
    expect(pair.window.operations, isEmpty);
    expect(pair.layout.palettePresentation.value, isNull);
  });

  test('close waits for final edit ACK and failure remains visible for retry',
      () async {
    await pair.open();
    pair.failEdit = true;
    pair.client.appearance.setBackgroundOpacity(.55);
    await pair.client.close();
    expect(pair.client.saveError.value, isNotNull);
    expect(pair.host.isOpen.value, isTrue);
    expect(pair.calls.where((c) => c.method == 'close'), isEmpty);
    pair.failEdit = false;
    await pair.client.close();
    await pair.opened;
    expect(pair.source.appearance.value.backgroundOpacity, .55);
  });

  test(
      'malformed snapshot is rejected atomically; later valid revision applies',
      () async {
    await pair.open();
    final before = pair.client.appearance.value;
    final malformed = {
      ...pair.snapshot!,
      'revision': 1000,
      'primary': 'wrong',
      'appearance': before.copyWith(backgroundOpacity: .8).toJson()
    };
    expect(pair.client.applySnapshot(malformed), isFalse);
    expect(pair.client.appearance.value, before);
    expect(pair.client.applySnapshot({...malformed, 'primary': 0xff009988}),
        isTrue);
    expect(pair.client.appearance.value.backgroundOpacity, .8);
    expect(
        pair.client.applySnapshot({
          ...malformed,
          'primary': 0xff009988,
          'fontFamilyFallback': [42]
        }),
        isFalse);
    await pair.end();
  });

  test('owner disposal removes handlers and late child edit cannot persist',
      () async {
    await pair.open();
    pair.host.dispose();
    await pair.opened;
    final count = pair.messages.length;
    expect(
        await _native(_hostChannel, 'edit', {
          'session': pair.snapshot!['session'],
          'sequence': 100,
          'patch': {'backgroundOpacity': .8}
        }),
        isNull);
    expect(pair.messages.length, count);
    expect(pair.window.operations, isEmpty);
  });

  test('close does not destroy the engine until its last patch is acknowledged',
      () async {
    await pair.open();
    final gate = pair.blockedEdit = Completer<Object?>();
    pair.client.appearance.setBackgroundOpacity(.65);
    final closing = pair.client.close();
    await Future<void>.delayed(Duration.zero);
    expect(pair.calls.where((c) => c.method == 'close'), isEmpty);
    expect(pair.host.isOpen.value, isTrue);
    gate.complete(null);
    await closing;
    await pair.opened;
    expect(pair.source.appearance.value.backgroundOpacity, .65);
    expect(pair.calls.where((c) => c.method == 'close'), hasLength(1));
  });

  test('startup timeout is terminal even if native first frame arrives late',
      () async {
    final gate = pair.blockedOpen = Completer<void>();
    await expectLater(pair.host.open(), throwsA(isA<TimeoutException>()));
    expect(pair.host.isOpen.value, isFalse);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(pair.host.isOpen.value, isFalse);
    expect(pair.window.operations, isEmpty);
    expect(pair.calls.where((c) => c.method == 'close'), hasLength(1));
  });

  test('disposed child ignores a late edit reply and cancels its timer',
      () async {
    await pair.open();
    final gate = pair.blockedEdit = Completer<Object?>();
    pair.client.appearance.setBackgroundOpacity(.25);
    final flush = pair.client.flush();
    await Future<void>.delayed(Duration.zero);
    pair.client.dispose();
    gate.complete(null);
    await flush;
    await pair.end();
    // The fixture tearDown also calls dispose, as route/engine teardown may do.
  });
}
