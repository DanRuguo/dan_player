import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:flutter/services.dart';

/// Font registration cannot be undone in Flutter. Load only visible rows or
/// an explicitly selected preview, share successful loads for this process,
/// and drop queued work as soon as its last visible consumer goes away.
class FontPreviewLoader {
  FontPreviewLoader({
    Future<void> Function(InstalledFont)? load,
    Future<int> Function(InstalledFont)? sizeOf,
    this.maximumAutomaticFonts = 64,
    this.maximumAutomaticBytes = 128 * 1024 * 1024,
  })  : _load = load ?? _loadInstalledFont,
        _sizeOf = sizeOf ?? (load == null ? _fileSize : (_) async => 0);

  static final instance = FontPreviewLoader();
  final Future<void> Function(InstalledFont) _load;
  final Future<int> Function(InstalledFont) _sizeOf;
  final int maximumAutomaticFonts;
  final int maximumAutomaticBytes;
  final _entries = <InstalledFont, _FontLoad>{};
  final _queue = Queue<_FontLoad>();
  int _active = 0;
  int _loadedFonts = 0;
  int _loadedBytes = 0;

  static Future<int> _fileSize(InstalledFont font) => File(font.path).length();

  String? loadedFamilyFor(InstalledFont font) => _entries[font]?.loadedFamily;

  static Future<void> _loadInstalledFont(InstalledFont font) async {
    final loader = FontLoader(font.fullName)
      ..addFont(File(font.path)
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  }

  FontPreviewLease acquire(InstalledFont font, {bool explicit = false}) {
    var entry = _entries[font];
    if (entry == null) {
      entry = _FontLoad(font);
      _entries[font] = entry;
      _queue.add(entry);
      scheduleMicrotask(_drain);
    }
    entry.explicit = entry.explicit || explicit;
    entry.users++;
    final requested = entry;
    return FontPreviewLease._(entry.result.future, () => requested.deferred,
        () {
      requested.users--;
      if (requested.users == 0 && !requested.started) {
        _queue.remove(requested);
        _entries.remove(requested.font);
        requested.result.complete(null);
      }
    });
  }

  void _drain() {
    while (_active < 2 && _queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      entry.started = true;
      _active++;
      _register(entry).then((family) {
        if (family == null) _entries.remove(entry.font);
        entry.loadedFamily = family;
        entry.result.complete(family);
      }, onError: (Object _, StackTrace __) {
        _entries.remove(entry.font);
        entry.result.complete(null);
      }).whenComplete(() {
        _active--;
        _drain();
      });
    }
  }

  Future<String?> _register(_FontLoad entry) async {
    if (!entry.explicit && _loadedFonts >= maximumAutomaticFonts) {
      entry.deferred = true;
      return null;
    }
    final bytes = await _sizeOf(entry.font);
    // A row/dialog can disappear while its file is being checked. Registering
    // the font after that would retain it in the engine for this whole process.
    // A new visible/selected consumer can still share the pending check.
    if (entry.users == 0) return null;
    if (!entry.explicit &&
        (_loadedFonts >= maximumAutomaticFonts ||
            _loadedBytes + bytes > maximumAutomaticBytes)) {
      entry.deferred = true;
      return null;
    }
    _loadedFonts++;
    _loadedBytes += bytes;
    try {
      await _load(entry.font);
      return entry.font.fullName;
    } catch (_) {
      _loadedFonts--;
      _loadedBytes -= bytes;
      rethrow;
    }
  }
}

class _FontLoad {
  _FontLoad(this.font);
  final InstalledFont font;
  final result = Completer<String?>();
  int users = 0;
  bool started = false;
  bool explicit = false;
  bool deferred = false;
  String? loadedFamily;
}

class FontPreviewLease {
  FontPreviewLease._(this.family, this._deferred, this._release);
  final Future<String?> family;
  final bool Function() _deferred;
  final void Function() _release;
  bool _released = false;
  bool get deferred => _deferred();

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}
