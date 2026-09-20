import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:path/path.dart' as p;

enum LibraryAvailability {
  available,
  sourceOffline,
  accessDenied,
  missing,
  unknown
}

class LibrarySourceHealth {
  const LibrarySourceHealth(this.root, this.availability,
      {this.lastSuccess, this.reason});
  final String root;
  final LibraryAvailability availability;
  final DateTime? lastSuccess;
  final String? reason;
  String get label => switch (availability) {
        LibraryAvailability.available => '可访问',
        LibraryAvailability.sourceOffline => '来源离线',
        LibraryAvailability.accessDenied => '访问受限',
        LibraryAvailability.missing => '目录缺失',
        LibraryAvailability.unknown => '状态待确认',
      };
}

class LibraryHealthReport {
  const LibraryHealthReport(this.sources,
      {this.checked = 0,
      this.missing = 0,
      this.denied = 0,
      this.pendingMetadata = 0,
      this.withoutCover = 0,
      this.unverified = 0,
      this.examples = const []});
  final List<LibrarySourceHealth> sources;
  final int checked, missing, denied, pendingMetadata, withoutCover, unverified;
  final List<String> examples;
}

/// Cheap on-demand checks. No fingerprinting, deletion, or metadata rewrite.
class LibraryHealthService {
  LibraryHealthService(this.directory);
  final Directory directory;
  File get _file => File(p.join(directory.path, 'library_health.json'));
  Future<({Map<String, dynamic> data, bool recovered})> _read() async {
    Object? failure;
    for (final candidate in [_file, File('${_file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        final raw = jsonDecode(await candidate.readAsString());
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('来源状态记录无法读取。');
        }
        final version = raw['version'];
        if (version is int && version > 1) {
          throw UnsupportedError(
              'Library health data was created by a newer version');
        }
        final sources = raw['sources'];
        if ((version != null && version != 1) ||
            (sources != null && sources is! Map)) {
          throw const FormatException('来源状态记录无法读取。');
        }
        for (final source in (sources as Map?)?.values ?? const []) {
          if (source is! Map ||
              const [
                'lastSuccess',
                'lastAttempt',
                'failure'
              ].any((key) => source[key] != null && source[key] is! String)) {
            throw const FormatException('来源状态记录无法读取。');
          }
        }
        return (data: raw, recovered: candidate.path != _file.path);
      } on UnsupportedError {
        // A future primary is not a corrupt snapshot. Never replace it with
        // an older backup on the next scan record.
        rethrow;
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
    return (data: <String, dynamic>{}, recovered: false);
  }

  Future<void> recordScan(Iterable<String> roots, {String? failure}) async {
    final snapshot = await _read();
    final sources =
        Map<String, dynamic>.from(snapshot.data['sources'] as Map? ?? {});
    final now = DateTime.now().toUtc().toIso8601String();
    for (final root in roots) {
      final old = Map<String, dynamic>.from(sources[root] as Map? ?? {});
      sources[root] = {
        ...old,
        if (failure == null) 'lastSuccess': now,
        'lastAttempt': now,
        'failure': failure == null ? null : '扫描未完整完成；保留上次索引'
      };
    }
    await directory.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    final backup = File('${_file.path}.bak');
    try {
      await temporary.writeAsString(
          jsonEncode({'version': 1, 'sources': sources}),
          flush: true);
      // Inspection never repairs files. The next successful record repairs
      // the primary while retaining the only known-good recovery copy.
      if (!snapshot.recovered && await _file.exists()) {
        if (await backup.exists()) await backup.delete();
        await _file.rename(backup.path);
      }
      await temporary.rename(_file.path);
    } catch (_) {
      if (!await _file.exists() && await backup.exists()) {
        await backup.copy(_file.path);
      }
      rethrow;
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on FileSystemException {
        // A cleanup failure must not replace the commit/rollback result.
      }
    }
  }

  Future<LibraryHealthReport> inspect(AudioLibrary library,
      {bool files = false,
      bool Function()? cancelled,
      void Function(int)? onProgress}) async {
    final previous = (await _read()).data['sources'] as Map? ?? {};
    final sources = <LibrarySourceHealth>[];
    for (final root in library.scanRoots) {
      if (cancelled?.call() == true) break;
      var state = LibraryAvailability.available;
      try {
        // Enumeration, unlike exists(), surfaces access denied separately.
        await Directory(root)
            .list(followLinks: false)
            .take(1)
            .drain<void>()
            .timeout(const Duration(seconds: 3));
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;
        state = code == 5 || code == 13
            ? LibraryAvailability.accessDenied
            : LibraryAvailability.sourceOffline;
      } catch (_) {
        state = LibraryAvailability.unknown;
      }
      final history = previous[root] as Map? ?? {};
      sources.add(LibrarySourceHealth(root, state,
          lastSuccess:
              DateTime.tryParse(history['lastSuccess'] as String? ?? ''),
          reason: history['failure'] as String?));
    }
    final audios = library.audioCollection.where((a) => a.isLocal).toList();
    var checked = 0, missing = 0, denied = 0, unknown = 0;
    final examples = <String>[];
    if (files) {
      // Four bounded requests avoid fan-out for network/cloud placeholders.
      var cursor = 0;
      await Future.wait(List.generate(4, (_) async {
        while (cursor < audios.length && cancelled?.call() != true) {
          final audio = audios[cursor++];
          final local = audio.localFilePath;
          final inaccessible = sources.any((s) =>
              s.availability != LibraryAvailability.available &&
              (p.windows.equals(s.root, local) ||
                  p.windows
                      .isWithin(s.root.toLowerCase(), local.toLowerCase())));
          if (inaccessible) {
            unknown++;
            continue;
          }
          try {
            final info =
                await File(local).stat().timeout(const Duration(seconds: 3));
            if (info.type != FileSystemEntityType.file) {
              missing++;
              if (examples.length < 10) examples.add(local);
            }
          } on FileSystemException catch (error) {
            if (error.osError?.errorCode == 5 ||
                error.osError?.errorCode == 13) {
              denied++;
            } else {
              unknown++;
            }
          } catch (_) {
            unknown++;
          }
          checked++;
          if (checked % 128 == 0) {
            onProgress?.call(checked);
            await Future<void>.delayed(Duration.zero);
          }
        }
      }));
      unknown += audios.length - cursor;
    }
    final missingCoverHashes = CoverCache.instance.recentArtworkMissHashes;
    return LibraryHealthReport(sources,
        checked: checked,
        missing: missing,
        denied: denied,
        unverified: files ? unknown : audios.length,
        pendingMetadata: audios.where((a) => a.metadataReadPending).length,
        withoutCover: audios
            .where((a) => missingCoverHashes
                .contains(CoverCache.stableHash(a.localFilePath)))
            .length,
        examples: examples);
  }
}
