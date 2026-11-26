import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

enum AppLogLevel {
  trace('TRACE'),
  debug('DEBUG'),
  info('INFO'),
  warning('WARN'),
  error('ERROR'),
  fatal('FATAL');

  const AppLogLevel(this.tag);
  final String tag;

  bool get isWarningOrAbove =>
      this == AppLogLevel.warning ||
      this == AppLogLevel.error ||
      this == AppLogLevel.fatal;

  static AppLogLevel fromLogger(Level level) {
    if (level.value >= Level.fatal.value) return AppLogLevel.fatal;
    if (level.value >= Level.error.value) return AppLogLevel.error;
    if (level.value >= Level.warning.value) return AppLogLevel.warning;
    if (level.value >= Level.info.value) return AppLogLevel.info;
    if (level.value >= Level.debug.value) return AppLogLevel.debug;
    return AppLogLevel.trace;
  }

  static AppLogLevel? tryParseTag(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'TRACE':
        return AppLogLevel.trace;
      case 'DEBUG':
        return AppLogLevel.debug;
      case 'INFO':
        return AppLogLevel.info;
      case 'WARN':
      case 'WARNING':
        return AppLogLevel.warning;
      case 'ERROR':
        return AppLogLevel.error;
      case 'FATAL':
      case 'WTF':
        return AppLogLevel.fatal;
      default:
        return null;
    }
  }
}

enum AppLogFilter { recent15Days, currentSession, warningsAndErrors }

class AppLogEntry {
  AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    required this.sessionOwned,
    this.repeatCount = 1,
  });

  DateTime timestamp;
  final AppLogLevel level;
  final String message;
  final bool sessionOwned;
  int repeatCount;

  static String formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    final ms = local.millisecond.toString().padLeft(3, '0');
    return '$y-$mo-$d $h:$mi:$s.$ms';
  }

  String format({
    bool redactPaths = false,
    Iterable<String> extraRoots = const [],
  }) {
    final sanitized = redactPaths
        ? AppLogService.redactSensitivePaths(message, extraRoots: extraRoots)
        : message;
    final lines = const LineSplitter().convert(sanitized);
    final head = lines.isEmpty ? '' : lines.first;
    final suffix = repeatCount > 1 ? ' (×$repeatCount)' : '';
    final buffer = StringBuffer()
      ..write('${formatTimestamp(timestamp)} [${level.tag}] $head$suffix');
    for (var i = 1; i < lines.length; i++) {
      buffer
        ..writeln()
        ..write('  ${lines[i]}');
    }
    return buffer.toString();
  }
}

/// Structured, timestamped ring + daily file logger with automatic 15-day
/// expiration. Coalesces disk writes so background diagnostics never cause
/// per-frame I/O wakeups or unbounded log growth.
class AppLogService {
  AppLogService._({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  @visibleForTesting
  factory AppLogService.forTesting({DateTime Function()? clock}) =>
      AppLogService._(clock: clock);

  static final AppLogService instance = AppLogService._();

  static const int retentionDays = 15;
  static const Duration retention = Duration(days: retentionDays);
  static const int maxMemoryEntries = 500;
  static const int maxLoadedHistoricalEntries = 280;
  static const int maxDailyFileBytes = 2 * 1024 * 1024;
  static const Duration _dedupWindow = Duration(seconds: 2);
  static const Duration _flushDelay = Duration(milliseconds: 450);

  static final RegExp _dailyFilePattern =
      RegExp(r'^danplayer-(\d{4})-(\d{2})-(\d{2})\.log$', caseSensitive: false);
  static final RegExp _headerLinePattern = RegExp(
      r'^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}\.\d{3}) \[([A-Z]+)\] (.*)$');
  static final RegExp _repeatSuffixPattern = RegExp(r' \(×(\d+)\)$');
  static final RegExp _windowsUserDirPattern =
      RegExp(r'([A-Za-z]:[\\/]+Users[\\/]+)([^\\/\r\n"<>|]+)',
          caseSensitive: false);
  static final RegExp _posixUserDirPattern =
      RegExp(r'(/(?:Users|home)/)([^/\r\n"<>|]+)');

  final DateTime Function() _clock;
  final ListQueue<AppLogEntry> _entries = ListQueue<AppLogEntry>();
  final ListQueue<AppLogEntry> _pendingEntries = ListQueue<AppLogEntry>();
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  Directory? _logsDirectory;
  Directory? _dataDirectory;
  Timer? _flushTimer;
  Future<void> _ioSerial = Future<void>.value();
  String? _lastPrunedDayKey;
  bool _initialized = false;

  ValueListenable<int> get revision => _revision;
  Directory? get logsDirectory => _logsDirectory;
  Directory? get dataDirectory => _dataDirectory;
  bool get isInitialized => _initialized;

  List<AppLogEntry> get entries => List<AppLogEntry>.unmodifiable(_entries);

  int countFor(AppLogFilter filter) => entriesFor(filter).length;

  int get warningOrErrorCount => countFor(AppLogFilter.warningsAndErrors);

  List<AppLogEntry> entriesFor(AppLogFilter filter) {
    final cutoff = _clock().subtract(retention);
    return _entries.where((entry) {
      if (entry.timestamp.isBefore(cutoff)) return false;
      return switch (filter) {
        AppLogFilter.recent15Days => true,
        AppLogFilter.currentSession => entry.sessionOwned,
        AppLogFilter.warningsAndErrors => entry.level.isWarningOrAbove,
      };
    }).toList(growable: false);
  }

  String formatEntries({
    AppLogFilter filter = AppLogFilter.recent15Days,
    bool redactPaths = true,
    Iterable<String> extraRoots = const [],
    int? maxEntries,
  }) {
    var selected = entriesFor(filter);
    if (maxEntries != null &&
        maxEntries > 0 &&
        selected.length > maxEntries) {
      selected = selected.sublist(selected.length - maxEntries);
    }
    if (selected.isEmpty) return '';
    final roots = <String>[
      if (_dataDirectory != null) _dataDirectory!.path,
      ...extraRoots,
    ];
    final out = StringBuffer();
    for (var i = 0; i < selected.length; i++) {
      if (i > 0) out.writeln();
      out.write(selected[i].format(
        redactPaths: redactPaths,
        extraRoots: roots,
      ));
    }
    return out.toString();
  }

  LogOutput createLoggerOutput({LogOutput? secondaryOutput}) =>
      _AppLogOutput(this, secondaryOutput);

  Future<void> initialize(
    Directory dataDirectory, {
    String? appVersion,
  }) {
    return _enqueueIo(() async {
      final normalizedData = Directory(p.normalize(dataDirectory.absolute.path));
      final logsDir = Directory(p.join(normalizedData.path, 'logs'));
      final switchedRoot = _logsDirectory == null ||
          !p.equals(_logsDirectory!.path, logsDir.path);
      _dataDirectory = normalizedData;
      _logsDirectory = logsDir;

      if (await FileSystemEntity.type(logsDir.path, followLinks: false) ==
          FileSystemEntityType.link) {
        _logsDirectory = null;
        return;
      }
      await logsDir.create(recursive: true);
      await _pruneExpiredLogsUnlocked(logsDir, _clock());

      if (!_initialized || switchedRoot) {
        final sessionSnapshot =
            _entries.where((entry) => entry.sessionOwned).toList();
        final historical = await _readRecentHistoricalEntries(logsDir, _clock());
        _entries
          ..clear()
          ..addAll(historical);
        for (final entry in sessionSnapshot) {
          _appendEntryMemoryOnly(entry);
        }
        _initialized = true;
        if (appVersion != null && appVersion.trim().isNotEmpty) {
          _recordInternal(
            AppLogLevel.info,
            '[session] Dan Player $appVersion started (${Platform.operatingSystem})',
            immediateFlush: false,
          );
        }
        _revision.value++;
      }

      if (_pendingEntries.isNotEmpty) {
        await _flushPendingUnlocked();
      }
    });
  }

  void record(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    DateTime? timestamp,
  }) {
    final composed = _composeMessage(message, error: error, stackTrace: stackTrace);
    if (composed.isEmpty) return;
    _recordInternal(
      level,
      composed,
      timestamp: timestamp,
      immediateFlush: level == AppLogLevel.error || level == AppLogLevel.fatal,
    );
  }

  void _recordOutputEvent(OutputEvent event) {
    final origin = event.origin;
    final level = AppLogLevel.fromLogger(origin.level);
    final rawMessage = origin.message is Function
        ? (origin.message as Object? Function())()?.toString() ?? ''
        : origin.message?.toString() ?? '';
    if (rawMessage.trim().isNotEmpty ||
        origin.error != null ||
        origin.stackTrace != null) {
      record(
        level,
        rawMessage,
        error: origin.error,
        stackTrace: origin.stackTrace,
        timestamp: origin.time,
      );
      return;
    }
    final joined = event.lines.join('\n').trim();
    if (joined.isEmpty) return;
    record(AppLogLevel.fromLogger(event.level), joined);
  }

  void _recordInternal(
    AppLogLevel level,
    String message, {
    DateTime? timestamp,
    required bool immediateFlush,
  }) {
    final now = (timestamp ?? _clock()).toLocal();
    final cutoff = now.subtract(retention);
    while (_entries.isNotEmpty && _entries.first.timestamp.isBefore(cutoff)) {
      _entries.removeFirst();
    }

    final entry = AppLogEntry(
      timestamp: now, level: level, message: message, sessionOwned: true,
    );
    _appendEntryMemoryOnly(entry);
    // Use a separate object for disk batches. A repeat arriving after the
    // previous batch was flushed must still be represented on the next launch.
    if (_pendingEntries.isEmpty || !_mergeRepeat(_pendingEntries.last, entry)) {
      _pendingEntries.add(AppLogEntry(
        timestamp: now, level: level, message: message, sessionOwned: true,
      ));
    }
    if (_logsDirectory == null && _pendingEntries.length > maxMemoryEntries) {
      _pendingEntries.removeFirst();
    }
    _revision.value++;

    if (_logsDirectory != null) {
      if (immediateFlush) {
        _flushTimer?.cancel();
        _flushTimer = null;
        unawaited(flush());
      } else {
        _flushTimer ??= Timer(_flushDelay, () {
          _flushTimer = null;
          unawaited(flush());
        });
      }
    }
  }

  static bool _mergeRepeat(AppLogEntry last, AppLogEntry entry) {
    final gap = entry.timestamp.difference(last.timestamp);
    if (last.level != entry.level || last.message != entry.message ||
        last.sessionOwned != entry.sessionOwned || gap.isNegative || gap > _dedupWindow) {
      return false;
    }
    last.timestamp = entry.timestamp;
    last.repeatCount += entry.repeatCount;
    return true;
  }

  void _appendEntryMemoryOnly(AppLogEntry entry) {
    if (_entries.isNotEmpty && _mergeRepeat(_entries.last, entry)) return;
    _entries.addLast(entry);
    while (_entries.length > maxMemoryEntries) {
      _entries.removeFirst();
    }
  }

  /// Deletes daily/legacy `.log` files older than [retention] (15 days) and
  /// evicts any expired in-memory entries. Returns the number of deleted files.
  Future<int> pruneExpiredLogs({DateTime? now}) {
    return _enqueueIo(() async {
      final current = (now ?? _clock()).toLocal();
      final cutoff = current.subtract(retention);
      var removedMemory = false;
      while (_entries.isNotEmpty && _entries.first.timestamp.isBefore(cutoff)) {
        _entries.removeFirst();
        removedMemory = true;
      }
      if (removedMemory) _revision.value++;
      final dir = _logsDirectory;
      if (dir == null) return 0;
      return _pruneExpiredLogsUnlocked(dir, current);
    });
  }

  Future<int> _pruneExpiredLogsUnlocked(Directory dir, DateTime current) async {
    if (await FileSystemEntity.type(dir.path, followLinks: false) != FileSystemEntityType.directory) return 0;
    final cutoff = current.subtract(retention);
    var deleted = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      final name = p.basename(entity.path);
      if (!name.toLowerCase().endsWith('.log')) continue;

      final match = _dailyFilePattern.firstMatch(name);
      DateTime referenceTime = stat.modified.toLocal();
      if (match != null) {
        final year = int.tryParse(match.group(1)!);
        final month = int.tryParse(match.group(2)!);
        final day = int.tryParse(match.group(3)!);
        if (year != null && month != null && day != null) {
          referenceTime = DateTime(year, month, day, 23, 59, 59, 999);
        }
      }
      if (!referenceTime.isAfter(cutoff)) {
        try {
          await File(entity.path).delete();
          deleted++;
        } on FileSystemException {
          // Ignore locked/transient deletion failures during active inspection.
        }
      }
    }
    _lastPrunedDayKey = _dayKeyFor(current);
    return deleted;
  }

  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    return _enqueueIo(_flushPendingUnlocked);
  }

  Future<void> _flushPendingUnlocked() async {
    final dir = _logsDirectory;
    if (dir == null || _pendingEntries.isEmpty) return;
    if (await FileSystemEntity.type(dir.path, followLinks: false) ==
        FileSystemEntityType.link) {
      _pendingEntries.clear();
      return;
    }
    await dir.create(recursive: true);
    final now = _clock().toLocal();
    final dayKey = _dayKeyFor(now);
    if (_lastPrunedDayKey != dayKey) {
      await _pruneExpiredLogsUnlocked(dir, now);
    }

    final file = File(p.join(dir.path, 'danplayer-$dayKey.log'));
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.link) {
      _pendingEntries.clear();
      return;
    }

    final payload = '${_pendingEntries.map((e) => e.format()).join('\n')}\n';
    _pendingEntries.clear();
    try {
      await file.writeAsString(payload, mode: FileMode.append, flush: true);
      final length = await file.length();
      if (length > maxDailyFileBytes) {
        await _trimLogFile(file, keepBytes: maxDailyFileBytes ~/ 2);
      }
    } on FileSystemException {
      // Never crash the player if disk space or permissions prevent log writes.
    }
  }

  Future<void> _trimLogFile(File file, {required int keepBytes}) async {
    final bytes = await file.readAsBytes();
    if (bytes.length <= keepBytes) return;
    var start = bytes.length - keepBytes;
    while (start < bytes.length && bytes[start] != 0x0A) {
      start++;
    }
    if (start < bytes.length && bytes[start] == 0x0A) start++;
    final trimmed = bytes.sublist(start);
    final temp = File('${file.path}.trim-tmp');
    await temp.writeAsBytes(trimmed, flush: true);
    await temp.rename(file.path);
  }

  Future<void> clearLogs() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingEntries.clear();
    return _enqueueIo(() async {
      _entries.clear();
      final dir = _logsDirectory;
      if (dir != null && await FileSystemEntity.type(dir.path, followLinks: false) == FileSystemEntityType.directory) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.log')) {
            try {
              await File(entity.path).delete();
            } on FileSystemException {
              // Ignore locked external readers.
            }
          }
        }
      }
      _revision.value++;
    });
  }

  Future<List<AppLogEntry>> _readRecentHistoricalEntries(
    Directory dir,
    DateTime now,
  ) async {
    if (!await dir.exists()) return const <AppLogEntry>[];
    final cutoff = now.subtract(retention);
    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && _dailyFilePattern.hasMatch(p.basename(entity.path))) {
        files.add(File(entity.path));
      }
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    final selected = ListQueue<AppLogEntry>();
    for (final file in files) {
      try {
        final content = await file.readAsString(encoding: utf8);
        final entries = _parseLogDocument(content, cutoff: cutoff);
        for (final entry in entries.reversed) {
          selected.addFirst(entry);
          if (selected.length == maxLoadedHistoricalEntries) break;
        }
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
      if (selected.length == maxLoadedHistoricalEntries) break;
    }
    final result = <AppLogEntry>[];
    for (final entry in selected) {
      if (result.isEmpty || !_mergeRepeat(result.last, entry)) result.add(entry);
    }
    return result;
  }

  static List<AppLogEntry> _parseLogDocument(
    String content, {
    required DateTime cutoff,
  }) {
    final result = <AppLogEntry>[];
    DateTime? activeTime;
    AppLogLevel? activeLevel;
    var activeRepeat = 1;
    final messageBuf = StringBuffer();

    void commit() {
      if (activeTime == null || activeLevel == null) return;
      if (!activeTime!.isBefore(cutoff)) {
        final text = messageBuf.toString().trimRight();
        if (text.isNotEmpty) {
          result.add(AppLogEntry(
            timestamp: activeTime!,
            level: activeLevel!,
            message: text,
            sessionOwned: false,
            repeatCount: activeRepeat,
          ));
        }
      }
      activeTime = null;
      activeLevel = null;
      activeRepeat = 1;
      messageBuf.clear();
    }

    for (final line in const LineSplitter().convert(content)) {
      final match = _headerLinePattern.firstMatch(line);
      if (match != null) {
        commit();
        final parsedTime =
            DateTime.tryParse('${match.group(1)!}T${match.group(2)!}');
        final parsedLevel = AppLogLevel.tryParseTag(match.group(3)!);
        if (parsedTime != null && parsedLevel != null) {
          activeTime = parsedTime;
          activeLevel = parsedLevel;
          var head = match.group(4)!;
          final repeatMatch = _repeatSuffixPattern.firstMatch(head);
          if (repeatMatch != null) {
            activeRepeat = int.tryParse(repeatMatch.group(1)!) ?? 1;
            head = head.substring(0, repeatMatch.start);
          }
          messageBuf.write(head);
          continue;
        }
      }
      if (activeTime != null) {
        messageBuf
          ..writeln()
          ..write(line.startsWith('  ') ? line.substring(2) : line);
      }
    }
    commit();
    return result;
  }

  static String _composeMessage(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final trimmed = message.trim();
    final parts = <String>[
      if (trimmed.isNotEmpty) trimmed,
      if (error != null && error.toString().trim() != trimmed)
        error.toString().trim(),
    ];
    if (stackTrace != null) {
      final traceLines = const LineSplitter()
          .convert(stackTrace.toString().trim())
          .where((line) => line.trim().isNotEmpty)
          .take(8)
          .toList(growable: false);
      if (traceLines.isNotEmpty) {
        parts.add(traceLines.join('\n'));
      }
    }
    return parts.join('\n');
  }

  static String redactSensitivePaths(
    String input, {
    Iterable<String> extraRoots = const [],
  }) {
    if (input.isEmpty) return input;
    var output = input;
    final normalizedRoots = extraRoots
        .map((r) => r.trim())
        .where((r) => r.length >= 4)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final root in normalizedRoots) {
      final escaped = RegExp.escape(root);
      output = output.replaceAll(
        RegExp(escaped, caseSensitive: !Platform.isWindows),
        '<APP_DATA>',
      );
      final slashNormalized = root.replaceAll('\\', '/');
      if (slashNormalized != root) {
        output = output.replaceAll(
          RegExp(RegExp.escape(slashNormalized),
              caseSensitive: !Platform.isWindows),
          '<APP_DATA>',
        );
      }
    }
    output = output.replaceAllMapped(
      _windowsUserDirPattern,
      (m) => '${m.group(1)}<USER>',
    );
    output = output.replaceAllMapped(
      _posixUserDirPattern,
      (m) => '${m.group(1)}<USER>',
    );
    return output;
  }

  static String _dayKeyFor(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Future<T> _enqueueIo<T>(Future<T> Function() action) {
    final next = _ioSerial.then((_) => action());
    _ioSerial = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}

class _AppLogOutput extends LogOutput {
  _AppLogOutput(this._service, this._secondary);

  final AppLogService _service;
  final LogOutput? _secondary;

  @override
  Future<void> init() async {
    await _secondary?.init();
  }

  @override
  void output(OutputEvent event) {
    _service._recordOutputEvent(event);
    _secondary?.output(event);
  }

  @override
  Future<void> destroy() async {
    await _secondary?.destroy();
  }
}
