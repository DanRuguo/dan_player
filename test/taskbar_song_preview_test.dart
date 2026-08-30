import 'dart:async';
import 'dart:typed_data';

import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/taskbar_song_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_integration.dart';

const first = TaskbarPreviewTrack(
    identity: 'a', title: '歌曲 A', artist: '艺术家', album: '专辑');
const second = TaskbarPreviewTrack(
    identity: 'b', title: '歌曲 B', artist: 'Artist', album: 'Album');
TaskbarThumbnail pixel(int value) =>
    TaskbarThumbnail(1, 1, Uint8List.fromList([value, 0, 0, 255]));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);

  test('pixel protocol rejects invalid dimensions and byte length', () {
    for (final (w, h, length) in [
      (0, 1, 0),
      (513, 1, 2052),
      (1, 513, 2052),
      (2, 2, 15),
      (-1, -1, 4)
    ]) {
      expect(
          () => TaskbarThumbnail(w, h, Uint8List(length)), throwsArgumentError);
    }
    expect(pixel(3).toMap().keys, ['width', 'height', 'pixels']);
  });

  test(
      'metadata identity excludes playback ticks and includes tag/cover revision',
      () {
    expect(
        first,
        const TaskbarPreviewTrack(
            identity: 'a', title: '歌曲 A', artist: '艺术家', album: '专辑'));
    expect(
        first,
        isNot(const TaskbarPreviewTrack(
            identity: 'a', title: '歌曲 A', artist: 'new', album: '专辑')));
  });

  test('publisher is passive, deduplicates and restores default on disable',
      () async {
    final calls = <String>[];
    var renders = 0;
    final publisher = TaskbarPreviewPublisher(invoke: (method, [args]) async {
      calls.add(method);
      return null;
    }, renderer: (_, __, ___) async {
      renders++;
      return pixel(1);
    });
    expect(calls, isEmpty);
    publisher.synchronize(enabled: true, scheme: scheme);
    expect(calls, isEmpty);
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    for (var i = 0; i < 100; i++) {
      publisher.synchronize(enabled: true, track: first, scheme: scheme);
    }
    await flushDesktopEvents();
    expect(renders, 1);
    expect(calls, ['setThumbnail']);
    publisher.synchronize(enabled: false, track: first, scheme: scheme);
    await flushDesktopEvents();
    expect(calls, ['setThumbnail', 'clearThumbnail']);
    await publisher.dispose();
    expect(calls, hasLength(2));
  });

  test('rapid songs coalesce to one render and cannot publish stale artwork',
      () async {
    final pending = Completer<TaskbarThumbnail>();
    final rendered = <TaskbarPreviewTrack>[];
    final values = <int>[];
    final publisher = TaskbarPreviewPublisher(invoke: (method, [args]) async {
      if (method == 'setThumbnail') {
        values.add((args!['pixels'] as Uint8List)[0]);
      }
      return null;
    }, renderer: (track, _, __) {
      rendered.add(track);
      return track == first ? pending.future : Future.value(pixel(2));
    });
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    for (var i = 0; i < 100; i++) {
      publisher.synchronize(
          enabled: true,
          track: TaskbarPreviewTrack(
              identity: i, title: '$i', artist: '', album: ''),
          scheme: scheme);
    }
    publisher.synchronize(enabled: true, track: second, scheme: scheme);
    expect(rendered, [first]);
    pending.complete(pixel(1));
    await flushDesktopEvents();
    expect(rendered, [first, second]);
    expect(values, [2]);
    await publisher.dispose();
  });

  test('closing does not await artwork and late result never reaches native',
      () async {
    final pending = Completer<TaskbarThumbnail>();
    final calls = <String>[];
    final publisher = TaskbarPreviewPublisher(
        invoke: (method, [args]) async {
          calls.add(method);
          return null;
        },
        renderer: (_, __, ___) => pending.future);
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await publisher.dispose();
    pending.complete(pixel(1));
    await flushDesktopEvents();
    expect(calls, isEmpty);
    publisher.synchronize(enabled: true, track: second, scheme: scheme);
    expect(calls, isEmpty);
  });

  test('a late disable failure cannot report an error for a new preview',
      () async {
    final pendingClear = Completer<Object?>();
    final errors = <Object>[];
    final calls = <String>[];
    final publisher = TaskbarPreviewPublisher(
      invoke: (method, [args]) {
        calls.add(method);
        if (method == 'clearThumbnail' && calls.length == 2) {
          return pendingClear.future;
        }
        return Future.value(null);
      },
      renderer: (_, __, ___) async => pixel(1),
      onError: errors.add,
    );
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    publisher.synchronize(enabled: false, scheme: scheme);
    await flushDesktopEvents();
    publisher.synchronize(enabled: true, track: second, scheme: scheme);
    pendingClear.completeError(StateError('Old clear failed'));
    await flushDesktopEvents();
    expect(calls, ['setThumbnail', 'clearThumbnail', 'setThumbnail']);
    expect(errors, isEmpty);
    await publisher.dispose();
  });

  test('disable after in-flight transport failure still clears native pixels',
      () async {
    final pendingSend = Completer<Object?>();
    final calls = <String>[];
    final publisher = TaskbarPreviewPublisher(
      invoke: (method, [args]) {
        calls.add(method);
        return method == 'setThumbnail'
            ? pendingSend.future
            : Future.value(null);
      },
      renderer: (_, __, ___) async => pixel(1),
    );
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    expect(calls, ['setThumbnail']);
    publisher.synchronize(enabled: false, scheme: scheme);
    pendingSend
        .completeError(StateError('transport failed after native mutation'));
    await flushDesktopEvents();
    expect(calls, ['setThumbnail', 'clearThumbnail']);
    await publisher.dispose();
  });

  test(
      'latest song replaces the card without clearing a pending native session',
      () async {
    final pendingSend = Completer<Object?>();
    final calls = <String>[];
    final rendered = <Object>[];
    const latest = TaskbarPreviewTrack(
        identity: 'c', title: 'Latest', artist: '', album: '');
    var ready = 0;
    final publisher = TaskbarPreviewPublisher(
      invoke: (method, [args]) {
        if (method == 'setThumbnail') {
          final value = (args!['pixels'] as Uint8List).first;
          calls.add('set:$value');
          if (value == 1) return pendingSend.future;
        } else {
          calls.add('clear');
        }
        return Future.value(null);
      },
      renderer: (track, _, __) async {
        rendered.add(track.identity);
        return pixel(track == first ? 1 : 3);
      },
      onReady: () => ready++,
    );
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    publisher.synchronize(enabled: true, track: second, scheme: scheme);
    publisher.synchronize(enabled: true, track: latest, scheme: scheme);
    expect(calls, ['set:1']);
    pendingSend.complete(null);
    await flushDesktopEvents();
    expect(rendered, ['a', 'c']);
    expect(calls, ['set:1', 'set:3']);
    expect(ready, 1);
    await publisher.dispose();
  });

  test('song changes keep the complete card until artwork resolves', () async {
    final pending = Completer<TaskbarThumbnail>();
    final calls = <String>[];
    final publisher = TaskbarPreviewPublisher(
      invoke: (method, [args]) async {
        calls.add(method == 'setThumbnail'
            ? 'set:${(args!['pixels'] as Uint8List).first}'
            : method);
        return null;
      },
      renderer: (track, _, __) =>
          track == first ? Future.value(pixel(1)) : pending.future,
    );
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    publisher.synchronize(enabled: true, track: second, scheme: scheme);
    await flushDesktopEvents();
    expect(calls, ['set:1']);
    pending.complete(pixel(2));
    await flushDesktopEvents();
    expect(calls, ['set:1', 'set:2']);
    await publisher.dispose();
    expect(calls, ['set:1', 'set:2', 'clearThumbnail']);
  });

  test('old send failure cannot clear the newer song card', () async {
    final failedSend = Completer<Object?>();
    final calls = <String>[];
    final errors = <Object>[];
    final publisher = TaskbarPreviewPublisher(
      invoke: (method, [args]) {
        calls.add(method);
        if (method == 'setThumbnail' &&
            (args!['pixels'] as Uint8List).first == 1) {
          return failedSend.future;
        }
        return Future.value(null);
      },
      renderer: (track, _, __) async => pixel(track == first ? 1 : 2),
      onError: errors.add,
    );
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    publisher.synchronize(enabled: true, track: second, scheme: scheme);
    failedSend.completeError(StateError('Old DWM request failed'));
    await flushDesktopEvents();
    expect(calls, ['setThumbnail', 'setThumbnail']);
    expect(errors, isEmpty);
    await publisher.dispose();
  });

  test('repeated theme and font changes do not tear down the native preview',
      () async {
    final calls = <String>[];
    final publisher = TaskbarPreviewPublisher(
      invoke: (method, [args]) async {
        calls.add(method);
        return null;
      },
      renderer: (_, __, ___) async => pixel(1),
    );
    for (var i = 0; i < 50; i++) {
      publisher.synchronize(
        enabled: true,
        track: i.isEven ? first : second,
        scheme: ColorScheme.fromSeed(seedColor: Colors.primaries[i % 18]),
        fontFamily: i.isEven ? 'DanPingFangSC' : 'Segoe UI',
      );
      await flushDesktopEvents();
    }
    expect(calls, List.filled(50, 'setThumbnail'));
    publisher.synchronize(enabled: true, scheme: scheme);
    await flushDesktopEvents();
    expect(calls.last, 'clearThumbnail');
    expect(calls.where((value) => value == 'clearThumbnail'), hasLength(1));
    await publisher.dispose();
  });

  test('dispose during native send clears once and never reports stale ready',
      () async {
    final pendingSend = Completer<Object?>();
    final calls = <String>[];
    var ready = 0;
    final publisher = TaskbarPreviewPublisher(
      invoke: (method, [args]) {
        calls.add(method);
        return method == 'setThumbnail'
            ? pendingSend.future
            : Future.value(null);
      },
      renderer: (_, __, ___) async => pixel(1),
      onReady: () => ready++,
    );
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    final closing = publisher.dispose();
    pendingSend.complete(null);
    await closing;
    expect(calls, ['setThumbnail', 'clearThumbnail']);
    expect(ready, 0);
    publisher.synchronize(enabled: true, track: second, scheme: scheme);
    await flushDesktopEvents();
    expect(calls, hasLength(2));
  });

  test('native failure clears custom preview and toggle permits retry',
      () async {
    var failing = true;
    var ready = 0;
    final errors = <Object>[];
    final calls = <String>[];
    final publisher = TaskbarPreviewPublisher(
        invoke: (method, [args]) async {
          calls.add(method);
          if (failing && method == 'setThumbnail') {
            throw StateError('DWM unavailable');
          }
          return null;
        },
        renderer: (_, __, ___) async => pixel(1),
        onError: errors.add,
        onReady: () => ready++);
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    expect(errors, hasLength(1));
    expect(calls, ['setThumbnail', 'clearThumbnail']);
    failing = false;
    publisher.synchronize(enabled: false, scheme: scheme);
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    expect(ready, 1);
    await publisher.dispose();
    expect(calls.last, 'clearThumbnail');
  });

  test('playback buttons do not wait for covers', () async {
    final native = FakeDesktopNative();
    final playback = FakeDesktopPlayback();
    final preferences = ValueNotifier(const PlayerExperiencePreferences());
    final pending = Completer<TaskbarThumbnail>();
    final integration = DesktopIntegration.forTesting(
        native: native,
        window: FakeDesktopWindow(native),
        playback: playback,
        preferences: preferences,
        previewRenderer: (_, __, ___) => pending.future);
    await integration.initialize(onExit: () async {});
    playback.value = const DesktopPlaybackSnapshot(
        ready: true, hasTrack: true, hasQueue: true, preview: first);
    await flushDesktopEvents();
    playback.value = const DesktopPlaybackSnapshot(
        ready: true,
        hasTrack: true,
        hasQueue: true,
        playing: true,
        preview: first);
    await flushDesktopEvents();
    expect(
        native.calls.lastWhere((e) => e.$1 == 'updatePlayback').$2!['playing'],
        true);
    expect(native.calls.where((e) => e.$1 == 'setThumbnail'), isEmpty);
    await integration.dispose();
    pending.complete(pixel(1));
    await flushDesktopEvents();
    expect(native.calls.where((e) => e.$1 == 'setThumbnail'), isEmpty);
    playback.dispose();
    preferences.dispose();
  });

  test('theme and font refresh the card without changing track', () async {
    final requests = <(ColorScheme, String)>[];
    final publisher = TaskbarPreviewPublisher(
        invoke: (_, [__]) async => null,
        renderer: (_, colors, font) async {
          requests.add((colors, font));
          return pixel(1);
        });
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    final dark = ColorScheme.fromSeed(
        seedColor: Colors.teal, brightness: Brightness.dark);
    publisher.synchronize(enabled: true, track: first, scheme: dark);
    await flushDesktopEvents();
    publisher.synchronize(
        enabled: true, track: first, scheme: dark, fontFamily: 'Custom');
    await flushDesktopEvents();
    expect(requests.map((e) => e.$1.brightness),
        [Brightness.light, Brightness.dark, Brightness.dark]);
    expect(requests.last.$2, 'Custom');
    await publisher.dispose();
  });

  test('renderer failure releases old native preview without retry loop',
      () async {
    final calls = <String>[];
    final errors = <Object>[];
    final publisher = TaskbarPreviewPublisher(
        invoke: (method, [args]) async {
          calls.add(method);
          return null;
        },
        renderer: (track, _, __) async {
          if (track == second) throw StateError('render failure');
          return pixel(1);
        },
        onError: errors.add);
    publisher.synchronize(enabled: true, track: first, scheme: scheme);
    await flushDesktopEvents();
    publisher.synchronize(enabled: true, track: second, scheme: scheme);
    await flushDesktopEvents();
    expect(calls, ['setThumbnail', 'clearThumbnail']);
    expect(errors, hasLength(1));
    publisher.synchronize(enabled: true, track: second, scheme: scheme);
    await flushDesktopEvents();
    expect(errors, hasLength(1));
    await publisher.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness production card is bounded and fully opaque',
        (tester) async {
      final colors =
          ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness);
      final card = await tester.runAsync(() => renderTaskbarSongPreview(
          TaskbarPreviewTrack(
              identity: 'render',
              title: '很长的歌曲名🎵' * 35,
              artist: '日本語 Artist 外文',
              album: '测试专辑'),
          colors,
          'DanPingFangSC'));
      expect(card!.width, 480);
      expect(card.height, 240);
      expect(card.pixels.length, 460800);
      for (var i = 3; i < card.pixels.length; i += 4) {
        if (card.pixels[i] != 255) fail('Transparent pixel at ${i ~/ 4}');
      }
      expect(card.pixels[0], (colors.surface.toARGB32() >> 16) & 255);
    });
  }

  test('preview preference round trip and damaged value safe fallback', () {
    final off =
        const PlayerExperiencePreferences().copyWith(taskbarSongPreview: false);
    expect(PlayerExperiencePreferences.fromMap(off.toMap()), off);
    expect(
        PlayerExperiencePreferences.fromMap(const {'taskbarSongPreview': 'bad'})
            .taskbarSongPreview,
        true);
    expect(off.taskbarControls, true);
  });
}
