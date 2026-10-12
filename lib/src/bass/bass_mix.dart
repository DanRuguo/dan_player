import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// BASS_MIXER_NODE is 16 bytes on Windows: QWORD, float, alignment padding.
final class BassMixerEnvelopeNode extends Struct {
  @Uint64()
  external int position;

  @Float()
  external double value;
}

/// Minimal BASSmix binding used by the persistent exclusive-output pipeline.
///
/// BASSmix is an add-on, not a codec plug-in: do not pass it to
/// BASS_PluginLoad. BASS must remain loaded until every mixer/source has been
/// released and this library is closed.
class BassMixLibrary {
  BassMixLibrary.open(String libraryPath)
      : _library = DynamicLibrary.open(libraryPath) {
    try {
      _getVersion = _library.lookupFunction<Uint32 Function(), int Function()>(
        'BASS_Mixer_GetVersion',
      );
      _streamCreate = _library.lookupFunction<
          Uint32 Function(Uint32, Uint32, Uint32),
          int Function(int, int, int)>('BASS_Mixer_StreamCreate');
      _streamAddChannel = _library.lookupFunction<
          Int32 Function(Uint32, Uint32, Uint32),
          int Function(int, int, int)>('BASS_Mixer_StreamAddChannel');
      _streamAddChannelEx = _library.lookupFunction<
          Int32 Function(Uint32, Uint32, Uint32, Uint64, Uint64),
          int Function(
              int, int, int, int, int)>('BASS_Mixer_StreamAddChannelEx');
      _channelGetMixer =
          _library.lookupFunction<Uint32 Function(Uint32), int Function(int)>(
              'BASS_Mixer_ChannelGetMixer');
      _channelSetEnvelope = _library.lookupFunction<
          Int32 Function(
              Uint32, Uint32, Pointer<BassMixerEnvelopeNode>, Uint32),
          int Function(int, int, Pointer<BassMixerEnvelopeNode>,
              int)>('BASS_Mixer_ChannelSetEnvelope');
      _channelSetEnvelopePosition = _library.lookupFunction<
          Int32 Function(Uint32, Uint32, Uint64),
          int Function(int, int, int)>('BASS_Mixer_ChannelSetEnvelopePos');
      _channelFlags = _library.lookupFunction<
          Uint32 Function(Uint32, Uint32, Uint32),
          int Function(int, int, int)>('BASS_Mixer_ChannelFlags');
      _channelIsActive =
          _library.lookupFunction<Uint32 Function(Uint32), int Function(int)>(
              'BASS_Mixer_ChannelIsActive');
      _channelRemove =
          _library.lookupFunction<Int32 Function(Uint32), int Function(int)>(
              'BASS_Mixer_ChannelRemove');
      _channelSetPosition = _library.lookupFunction<
          Int32 Function(Uint32, Uint64, Uint32),
          int Function(int, int, int)>('BASS_Mixer_ChannelSetPosition');
      _channelGetPosition = _library.lookupFunction<
          Uint64 Function(Uint32, Uint32),
          int Function(int, int)>('BASS_Mixer_ChannelGetPosition');
      if ((_getVersion() >> 16) != 0x0204) {
        throw StateError('BASSmix 版本不兼容，需要 2.4 系列');
      }
    } catch (_) {
      _library.close();
      rethrow;
    }
  }

  final DynamicLibrary _library;
  late final int Function() _getVersion;
  late final int Function(int, int, int) _streamCreate;
  late final int Function(int, int, int) _streamAddChannel;
  late final int Function(int, int, int, int, int) _streamAddChannelEx;
  late final int Function(int) _channelGetMixer;
  late final int Function(int, int, Pointer<BassMixerEnvelopeNode>, int)
      _channelSetEnvelope;
  late final int Function(int, int, int) _channelSetEnvelopePosition;
  late final int Function(int, int, int) _channelFlags;
  late final int Function(int) _channelIsActive;
  late final int Function(int) _channelRemove;
  late final int Function(int, int, int) _channelSetPosition;
  late final int Function(int, int) _channelGetPosition;
  bool _closed = false;

  static const int nonstop = 0x20000;
  static const int resume = 0x1000;
  static const int queue = 0x8000;
  static const int end = 0x10000;
  static const int channelAbsolute = 0x1000;
  static const int channelPaused = 0x20000;
  static const int channelDownmix = 0x400000;
  static const int channelNoRampIn = 0x800000;
  static const int envelopeVolume = 2;
  static const int positionMixerReset = 0x10000;
  static const int errorValue = 0xffffffff;

  int get version => _getVersion();

  int createStream(int frequency, int channels, int flags) {
    if (_closed) throw StateError('BASSmix 已关闭');
    return _streamCreate(frequency, channels, flags);
  }

  bool addChannel(int mixer, int source,
          {bool paused = true, bool noRampIn = false}) =>
      _streamAddChannel(
        mixer,
        source,
        channelDownmix |
            (paused ? channelPaused : 0) |
            (noRampIn ? channelNoRampIn : 0),
      ) !=
      0;

  bool addChannelEx(int mixer, int source,
      {required int startByte,
      int lengthBytes = 0,
      bool absolute = true,
      bool paused = false,
      bool noRampIn = true}) {
    if (_closed) throw StateError('BASSmix 已关闭');
    return _streamAddChannelEx(
            mixer,
            source,
            channelDownmix |
                (absolute ? channelAbsolute : 0) |
                (paused ? channelPaused : 0) |
                (noRampIn ? channelNoRampIn : 0),
            startByte,
            lengthBytes) !=
        0;
  }

  int getChannelMixer(int source) {
    if (_closed) throw StateError('BASSmix 已关闭');
    return _channelGetMixer(source);
  }

  /// Positions use the mixer output format. Native BASSmix copies the nodes,
  /// so the temporary array is released immediately; an empty list removes it.
  bool setVolumeEnvelope(int source, List<(int, double)> nodes) {
    if (_closed) throw StateError('BASSmix 已关闭');
    if (nodes.isEmpty) {
      return _channelSetEnvelope(source, envelopeVolume, nullptr, 0) != 0;
    }
    final memory = calloc<BassMixerEnvelopeNode>(nodes.length);
    try {
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        if (node.$1 < 0 ||
            !node.$2.isFinite ||
            (i > 0 && node.$1 < nodes[i - 1].$1)) {
          throw ArgumentError('Invalid BASSmix envelope node');
        }
        memory[i]
          ..position = node.$1
          ..value = node.$2;
      }
      return _channelSetEnvelope(
              source, envelopeVolume, memory, nodes.length) !=
          0;
    } finally {
      calloc.free(memory);
    }
  }

  bool setVolumeEnvelopePosition(int source, int position) {
    if (_closed) throw StateError('BASSmix 已关闭');
    return _channelSetEnvelopePosition(source, envelopeVolume, position) != 0;
  }

  /// Returns the updated flags, or [errorValue] on failure.
  int setChannelPaused(int source, bool paused) => _channelFlags(
        source,
        paused ? channelPaused : 0,
        channelPaused,
      );

  int channelIsActive(int source) => _channelIsActive(source);

  bool removeChannel(int source) => _channelRemove(source) != 0;

  bool setChannelPosition(int source, int position, int mode) =>
      _channelSetPosition(source, position, mode) != 0;

  int getChannelPosition(int source, int mode) =>
      _channelGetPosition(source, mode);

  /// Call only after all mixer streams have been freed.
  void close() {
    if (_closed) return;
    _closed = true;
    _library.close();
  }
}
