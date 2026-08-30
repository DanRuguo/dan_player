import 'dart:ffi';

/// The separately licensed BASS_FX extension. It is not a codec plugin and
/// must not be passed to BASS_PluginLoad. BASS must already be loaded.
class BassTempoLibrary {
  BassTempoLibrary.open(String libraryPath)
      : _library = DynamicLibrary.open(libraryPath) {
    try {
      _create = _library.lookupFunction<Uint32 Function(Uint32, Uint32),
          int Function(int, int)>('BASS_FX_TempoCreate');
      _getVersion = _library.lookupFunction<Uint32 Function(), int Function()>(
          'BASS_FX_GetVersion');
      if ((_getVersion() >> 16) != 0x0204) {
        throw StateError('BASS_FX 版本不兼容，需要 2.4 系列');
      }
    } catch (_) {
      _library.close();
      rethrow;
    }
  }

  final DynamicLibrary _library;
  late final int Function(int, int) _create;
  late final int Function() _getVersion;
  bool _closed = false;

  static const tempoAttribute = 0x10000;
  static const preventClickAttribute = 0x10016;
  static const _freeSource = 0x10000;
  static const _float = 0x100;
  static const _decode = 0x200000;

  int get version => _getVersion();

  /// A successful wrapper owns [source] (FREESOURCE); a failed call leaves
  /// ownership with the caller. Free the returned handle with BASS_StreamFree.
  int createStream(int source, {required bool decodingOutput}) {
    if (_closed) throw StateError('BASS_FX 已关闭');
    return _create(
        source, _freeSource | _float | (decodingOutput ? _decode : 0));
  }

  /// Call only after every tempo stream and BASS device has been released.
  void close() {
    if (_closed) return;
    _closed = true;
    _library.close();
  }
}
