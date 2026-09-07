import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// BASS_ERROR_INIT permits one reinitialization; neither unknown failures nor
/// repeated INIT responses may recurse forever on the UI isolate.
int startBassDeviceOnce({
  required int Function() start,
  required int Function() errorCode,
  required void Function() initialize,
}) {
  if (start() != 0) return 0;
  var error = errorCode();
  if (error == 8) {
    initialize();
    if (start() != 0) return 0;
    error = errorCode();
  }
  return error == 0 ? -1 : error;
}

/// ABI layouts from the bundled BASS 2.4 headers / official BASS documentation.
final class BassChannelInfo extends Struct {
  @Uint32()
  external int frequency;
  @Uint32()
  external int channels;
  @Uint32()
  external int flags;
  @Uint32()
  external int channelType;
  @Uint32()
  external int originalResolution;
  @Uint32()
  external int plugin;
  @Uint32()
  external int sample;
  external Pointer<Void> filename;
}

final class BassWasapiInfo extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int frequency;
  @Uint32()
  external int channels;
  @Uint32()
  external int format;
  @Uint32()
  external int bufferBytes;
  @Float()
  external double volumeMax;
  @Float()
  external double volumeMin;
  @Float()
  external double volumeStep;
}

class BassFormatSnapshot {
  const BassFormatSnapshot({
    required this.sampleRate,
    required this.channels,
    this.originalBits,
    this.decoderType,
    this.sampleFormat,
    this.bufferBytes,
    this.exclusive,
  });
  final int sampleRate;
  final int channels;
  final int? originalBits;
  final int? decoderType;
  final String? sampleFormat;
  final int? bufferBytes;
  final bool? exclusive;

  Map<String, Object?> toJson() => {
        'sampleRate': sampleRate,
        'channels': channels,
        'originalBits': originalBits,
        'decoderType': decoderType,
        'sampleFormat': sampleFormat,
        'bufferBytes': bufferBytes,
        'exclusive': exclusive,
      };
}

BassFormatSnapshot? readBassChannelFormat(DynamicLibrary library, int stream) {
  final read = library.lookupFunction<
      Int32 Function(Uint32, Pointer<BassChannelInfo>),
      int Function(int, Pointer<BassChannelInfo>)>('BASS_ChannelGetInfo');
  final info = calloc<BassChannelInfo>();
  try {
    if (read(stream, info) == 0) return null;
    final bits = info.ref.originalResolution & 0xffff;
    return BassFormatSnapshot(
      sampleRate: info.ref.frequency,
      channels: info.ref.channels,
      originalBits: bits == 0 ? null : bits,
      decoderType: info.ref.channelType,
      sampleFormat: info.ref.flags & 0x100 != 0
          ? 'float32'
          : info.ref.flags & 1 != 0
              ? 'int8'
              : 'int16',
    );
  } finally {
    calloc.free(info);
  }
}

BassFormatSnapshot? readBassWasapiFormat(DynamicLibrary library) {
  final read = library.lookupFunction<Int32 Function(Pointer<BassWasapiInfo>),
      int Function(Pointer<BassWasapiInfo>)>('BASS_WASAPI_GetInfo');
  final info = calloc<BassWasapiInfo>();
  try {
    if (read(info) == 0) return null;
    return BassFormatSnapshot(
      sampleRate: info.ref.frequency,
      channels: info.ref.channels,
      sampleFormat: switch (info.ref.format) {
        0 => 'float32',
        1 => 'int8',
        2 => 'int16',
        3 => 'int24',
        4 => 'int32',
        _ => null,
      },
      bufferBytes: info.ref.bufferBytes,
      exclusive: info.ref.flags & 1 != 0,
    );
  } finally {
    calloc.free(info);
  }
}
