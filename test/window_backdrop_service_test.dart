import 'dart:async';

import 'package:dan_player/window_backdrop.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> _response({
  bool dark = false,
  bool available = true,
  String? reason,
}) =>
    {
      'available': available,
      'effect': available ? 'acrylic' : 'solid',
      'dark': dark,
      'fallbackColor': dark ? 0xFF202020 : 0xFFF3F3F3,
      if (reason != null) 'reason': reason,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannel channel;
  late WindowBackdropService service;
  var sequence = 0;

  setUp(() {
    channel = MethodChannel('test/window_backdrop/${sequence++}');
    service = WindowBackdropService.forTesting(channel: channel);
  });
  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> emit(Map<String, Object> data) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('stateChanged', data)),
      (_) {},
    );
  }

  test('brightness before native window readiness does not configure a policy',
      () async {
    final requests = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      requests.add(call.arguments);
      return _response(dark: true);
    });
    await service.setBrightness(Brightness.dark);
    expect(requests, isEmpty);
    expect(service.value.available, isFalse);
    await service.initialize(brightness: Brightness.dark);
    expect(requests, [
      {'dark': true, 'enabled': true}
    ]);
    expect(service.value.available, isTrue);
    await service.setBrightness(Brightness.dark);
    expect(requests, hasLength(1));
  });

  test('unsupported platforms do not invoke the native channel', () async {
    service.dispose();
    service = WindowBackdropService.forTesting(
        channel: channel, supportedPlatform: false);
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return _response();
    });
    await service.initialize(brightness: Brightness.light);
    expect(calls, 0);
    expect(service.value.reason, 'unsupported_platform');
  });

  test('off/on preferences are serialized and unchanged values do not reapply',
      () async {
    final requests = <Map>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final request = call.arguments as Map;
      requests.add(request);
      final enabled = request['enabled'] == true;
      return {
        ..._response(
            dark: request['dark'] == true,
            available: enabled,
            reason: enabled ? null : 'disabled'),
        'enabled': enabled,
      };
    });
    await service.initialize(brightness: Brightness.light, enabled: false);
    expect(service.value.reason, 'disabled');
    await service.configure(brightness: Brightness.light, enabled: false);
    expect(requests, hasLength(1));
    await service.configure(brightness: Brightness.light, enabled: true);
    expect(requests, hasLength(2));
    expect(service.value.available, isTrue);
    await emit({
      ..._response(available: false, reason: 'old_disabled'),
      'enabled': false
    });
    expect(service.value.available, isTrue,
        reason: 'Stale source events must not override current policy');
    await service.setBrightness(Brightness.dark);
    expect(requests.last, {'dark': true, 'enabled': true});
  });

  test('an enabled mismatch in a configure reply fails closed', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              ..._response(),
              'enabled': false,
            });
    await service.initialize(brightness: Brightness.light);
    expect(service.value.reason, 'invalid_response');
  });

  test('rapid brightness changes serialize and skip obsolete queued requests',
      () async {
    final started = Completer<void>();
    final firstResponse = Completer<Object?>();
    final requests = <bool>[];
    final published = <WindowBackdropStatus>[];
    service.addListener(() => published.add(service.value));
    messenger.setMockMethodCallHandler(channel, (call) async {
      final dark = (call.arguments as Map)['dark'] as bool;
      requests.add(dark);
      if (requests.length == 1) {
        started.complete();
        return firstResponse.future;
      }
      return _response(dark: dark);
    });
    final first = service.initialize(brightness: Brightness.light);
    await started.future;
    final second = service.setBrightness(Brightness.dark);
    final third = service.setBrightness(Brightness.light);
    firstResponse.complete(_response(available: false, reason: 'old_result'));
    await Future.wait([first, second, third]);
    expect(requests, [false, false]);
    expect(service.value.available, isTrue);
    expect(published.any((value) => value.reason == 'old_result'), isFalse);
  });

  test('a system settings event outranks an in-flight configure response',
      () async {
    final started = Completer<void>();
    final reply = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      started.complete();
      return reply.future;
    });
    final initialize = service.initialize(brightness: Brightness.light);
    await started.future;
    await emit(_response(available: false, reason: 'transparency_disabled'));
    reply.complete(_response());
    await initialize;
    expect(service.value.available, isFalse);
    expect(service.value.reason, 'transparency_disabled');
    await emit(_response());
    expect(service.value.available, isTrue);
  });

  test('late events for a previous brightness are ignored', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => _response());
    await service.initialize(brightness: Brightness.light);
    await emit(
        _response(dark: true, available: false, reason: 'old_dark_policy'));
    expect(service.value.available, isTrue);
  });

  test('a mismatched configure response fails closed', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => _response(dark: true));
    await service.initialize(brightness: Brightness.light);
    expect(service.value.available, isFalse);
    expect(service.value.reason, 'invalid_response');
  });

  test('high contrast fallback uses an opaque system colour', () async {
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
              ..._response(available: false, reason: 'high_contrast'),
              'fallbackColor': 0x00123456,
            });
    await service.initialize(brightness: Brightness.light);
    expect(service.value.fallbackColor!.toARGB32(), 0xFF123456);
    expect(service.value.description, contains('高对比度'));
  });

  test('native energy-saver reason explains the opaque fallback', () {
    final status = WindowBackdropStatus.fromMessage(
      _response(available: false, reason: 'energy_saver'),
    );
    expect(status.available, isFalse);
    expect(status.description, contains('节电模式'));
  });

  for (final effect in ['mica', 'transparent', 'solid', '', null]) {
    test('available response with non-desktop-blur effect $effect is rejected',
        () async {
      messenger.setMockMethodCallHandler(
          channel,
          (_) async => {
                'available': true,
                'effect': effect,
              });
      await service.initialize(brightness: Brightness.light);
      expect(service.value.available, isFalse);
      expect(service.value.reason, 'invalid_response');
    });
  }

  test('missing native plugin retains a readable fallback', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw MissingPluginException());
    await service.initialize(brightness: Brightness.light);
    expect(service.value.available, isFalse);
    expect(service.value.reason, 'unsupported_platform');
  });

  test('native errors retain a readable fallback', () async {
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'failed'));
    await service.initialize(brightness: Brightness.light);
    expect(service.value.available, isFalse);
    expect(service.value.reason, 'backend_error');
  });

  test('native timeout does not block startup indefinitely', () async {
    service.dispose();
    service = WindowBackdropService.forTesting(
        channel: channel, timeout: const Duration(milliseconds: 20));
    final reply = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => reply.future);
    await service.initialize(brightness: Brightness.light);
    expect(service.value.available, isFalse);
    expect(service.value.reason, 'backend_timeout');
    reply.complete(_response());
  });

  test('late native completion after dispose does not notify or throw',
      () async {
    final started = Completer<void>();
    final reply = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) async {
      started.complete();
      return reply.future;
    });
    var notifications = 0;
    service.addListener(() => notifications++);
    final initialize = service.initialize(brightness: Brightness.light);
    await started.future;
    service.dispose();
    reply.complete(_response());
    await initialize;
    expect(notifications, 0);
    // Keep tearDown owning a live, independent notifier.
    service = WindowBackdropService.forTesting(channel: channel);
  });
}
