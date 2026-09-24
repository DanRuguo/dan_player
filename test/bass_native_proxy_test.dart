import 'dart:ffi' as native;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dll = Platform.environment['DAN_PLAYER_BASS_DLL'];
  test('native BASS can open a WAV through custom proxy and bypass loopback',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final wave = _silenceWave();
    final subscription = server.listen((request) async {
      requests++;
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response.contentLength = wave.length;
      request.response.add(wave);
      await request.response.close();
    });
    const policy = NetworkProxyPreferences(
        mode: NetworkProxyMode.custom, customProxyUrl: 'http://127.0.0.1:7890');
    try {
      final remote = Uri.http('example.invalid', '/sample.wav');
      final proxy = '127.0.0.1:${server.port}';
      expect(bassProxyForUrl(remote, policy), '127.0.0.1:7890');
      final proxied = await Isolate.run(
          () => _openNativeBassUrl(dll!, remote.toString(), proxy));
      expect(proxied, 'ok');

      final local = Uri.http('127.0.0.1:${server.port}', '/sample.wav');
      final directProxy = bassProxyForUrl(local, policy);
      expect(directProxy, isNull);
      final direct = await Isolate.run(
          () => _openNativeBassUrl(dll!, local.toString(), directProxy));
      expect(direct, 'ok');
      expect(requests, 2);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  },
      skip: !Platform.isWindows || dll == null,
      timeout: const Timeout(Duration(seconds: 20)));
}

String _openNativeBassUrl(String dll, String url, String? proxy) {
  final library = native.DynamicLibrary.open(dll);
  final init = library.lookupFunction<
      native.Int32 Function(native.Int32, native.Uint32, native.Uint32,
          native.Pointer<native.Void>, native.Pointer<native.Void>),
      int Function(int, int, int, native.Pointer<native.Void>,
          native.Pointer<native.Void>)>('BASS_Init');
  final free = library
      .lookupFunction<native.Int32 Function(), int Function()>('BASS_Free');
  final error = library.lookupFunction<native.Int32 Function(), int Function()>(
      'BASS_ErrorGetCode');
  final setProxy = library.lookupFunction<
      native.Int32 Function(native.Uint32, native.Pointer<native.Void>),
      int Function(int, native.Pointer<native.Void>)>('BASS_SetConfigPtr');
  final getProxy = library.lookupFunction<
      native.Pointer<native.Void> Function(native.Uint32),
      native.Pointer<native.Void> Function(int)>('BASS_GetConfigPtr');
  final create = library.lookupFunction<
      native.Uint32 Function(
          native.Pointer<native.Void>,
          native.Uint32,
          native.Uint32,
          native.Pointer<native.Void>,
          native.Pointer<native.Void>),
      int Function(
          native.Pointer<native.Void>,
          int,
          int,
          native.Pointer<native.Void>,
          native.Pointer<native.Void>)>('BASS_StreamCreateURL');
  final streamFree = library.lookupFunction<
      native.Int32 Function(native.Uint32),
      int Function(int)>('BASS_StreamFree');
  final urlPointer = url.toNativeUtf16().cast<native.Void>();
  native.Pointer<native.Void>? proxyPointer =
      proxy?.toNativeUtf16().cast<native.Void>();
  try {
    if (init(0, 44100, 0, native.nullptr, native.nullptr) == 0) {
      return 'init:${error()}';
    }
    if (setProxy(17 | 0x80000000, proxyPointer ?? native.nullptr) == 0 &&
        !(proxy == null && getProxy(17) == native.nullptr)) {
      final code = error();
      return 'proxy:$code';
    }
    // BASS copies this string; stream creation must still use the proxy.
    if (proxyPointer != null) {
      ffi.malloc.free(proxyPointer);
      proxyPointer = null;
    }
    final stream = create(
        urlPointer, 0, 0x80000000 | 0x200000, native.nullptr, native.nullptr);
    if (stream == 0) return 'open:${error()}';
    streamFree(stream);
    return 'ok';
  } finally {
    free();
    ffi.malloc.free(urlPointer);
    if (proxyPointer != null) ffi.malloc.free(proxyPointer);
    library.close();
  }
}

Uint8List _silenceWave() {
  const samples = 800;
  const dataLength = samples * 2;
  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  return bytes;
}
