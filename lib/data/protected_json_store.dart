import 'dart:convert';
import 'dart:io';

/// Small authoritative user documents. A failed commit never publishes memory;
/// unknown versions block writes rather than falling back to older contents.
class ProtectedJsonStore {
  ProtectedJsonStore(this.file,
      {required this.validate, this.maxBytes = 8 * 1024 * 1024});
  final File file;
  final void Function(Map<String, dynamic>) validate;
  final int maxBytes;
  static Future<void> _snapshotTail = Future.value();
  static Future<T> withSnapshot<T>(Future<T> Function() action) {
    final next = _snapshotTail.then((_) => action());
    _snapshotTail =
        next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _pending = Future.value();
  Map<String, dynamic>? _value;
  bool _recovered = false;
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> flush() => _pending;
  Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  Future<void> _load() async {
    if (_value != null) return;
    Object? error;
    for (final candidate in [file, File('${file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        if (await candidate.length() > maxBytes)
          throw const FormatException('User data exceeds capacity');
        final raw = jsonDecode(await candidate.readAsString());
        if (raw is Map && raw['version'] is int && raw['version'] > 1) {
          throw UnsupportedError('User data was created by a newer version');
        }
        final value = Map<String, dynamic>.from(raw as Map);
        validate(value);
        _value = value;
        _recovered = candidate.path != file.path;
        return;
      } on UnsupportedError {
        rethrow;
      } catch (failure) {
        error = failure;
      }
    }
    if (error != null) throw error;
    _value = {'version': 1};
  }

  Future<Map<String, dynamic>> snapshot() => _serial(() async {
        await _load();
        return _copy(_value!);
      });
  Future<void> update(void Function(Map<String, dynamic>) edit) =>
      _serial(() => withSnapshot(() async {
            await _load();
            final next = _copy(_value!);
            edit(next);
            validate(next);
            final contents = jsonEncode(next);
            if (utf8.encode(contents).length > maxBytes)
              throw StateError('User data capacity reached');
            final temporary = File('${file.path}.tmp');
            final backup = File('${file.path}.bak');
            await file.parent.create(recursive: true);
            try {
              await temporary.writeAsString(contents, flush: true);
              if (!_recovered && await file.exists()) {
                if (await backup.exists()) await backup.delete();
                await file.rename(backup.path);
              }
              await temporary.rename(file.path);
              _value = next;
              _recovered = false;
            } catch (_) {
              if (!await file.exists() && await backup.exists())
                await backup.copy(file.path);
              rethrow;
            } finally {
              if (await temporary.exists()) await temporary.delete();
            }
          }));
}
