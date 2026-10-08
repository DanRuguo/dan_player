import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter/foundation.dart';

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
        value.map((key, item) => MapEntry(key as String, _freeze(item))));
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

/// One coherent, immutable display capture. The recorder continues separately.
class StatisticsDisplaySnapshot {
  StatisticsDisplaySnapshot._({
    required this.playbackData,
    required this.library,
    required this.capturedAt,
    required this.libraryRevision,
    required this.storageWarning,
    required this.personalSummary,
    required this.personalWarning,
  });

  final Map<String, Object?> playbackData;
  final LibraryStatisticsSnapshot library;
  final DateTime capturedAt;
  final int libraryRevision;
  final String? storageWarning;
  final PersonalOrganizationSummary? personalSummary;
  final Object? personalWarning;
}

/// Application-session display cache. Neither library changes nor recording
/// notifications refresh it. Only startup and an explicit refresh do that.
class StatisticsDisplayService extends ChangeNotifier {
  StatisticsDisplayService({
    PlaybackStatistics? statistics,
    LibraryStatisticsScanner? scanner,
    List<Audio> Function()? readLibrary,
    int Function()? readLibraryRevision,
    FutureOr<Map<String, PersonalTrack>> Function()? readPersonal,
    DateTime Function()? clock,
  })  : _statistics = statistics ?? PlaybackStatistics.instance,
        _scanner = scanner ?? LibraryStatisticsScanner(),
        _readLibrary =
            readLibrary ?? (() => AudioLibrary.instance.audioCollection),
        _readLibraryRevision =
            readLibraryRevision ?? (() => AudioLibrary.revision),
        _readPersonal = readPersonal ?? (() => PersonalLibrary.latest),
        _clock = clock ?? DateTime.now;

  static final instance = StatisticsDisplayService(
      readPersonal: () async => (await PersonalLibrary.instance).snapshot());

  final PlaybackStatistics _statistics;
  final LibraryStatisticsScanner _scanner;
  final List<Audio> Function() _readLibrary;
  final int Function() _readLibraryRevision;
  final FutureOr<Map<String, PersonalTrack>> Function() _readPersonal;
  final DateTime Function() _clock;
  StatisticsDisplaySnapshot? _snapshot;
  Future<void>? _pending;
  bool _prewarmed = false;
  bool _disposed = false;
  bool _refreshing = false;
  Object? _failure;
  int _completed = 0;
  int _total = 0;

  StatisticsDisplaySnapshot? get snapshot => _snapshot;
  bool get refreshing => _refreshing;
  Object? get failure => _failure;
  int get completed => _completed;
  int get total => _total;

  /// The startup caller schedules this after the first usable player frame.
  /// Repeated startup callbacks reuse the same in-flight/result capture.
  Future<void> prewarmOnce() {
    if (_prewarmed || _disposed) return _pending ?? Future<void>.value();
    _prewarmed = true;
    return refresh();
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    if (_pending != null) return _pending!;
    _prewarmed = true;
    // Capture before the scanner's first await, matching its frozen library
    // descriptors. Plays recorded during scanning belong to the next refresh.
    final playbackData =
        _freeze(_statistics.snapshot()) as Map<String, Object?>;
    final audios = List<Audio>.of(_readLibrary());
    final trackIds =
        List<String>.unmodifiable(audios.map((audio) => audio.stableTrackId));
    final capturedAt = _clock();
    final revision = _readLibraryRevision();
    final warning = _statistics.storageWarning;
    _refreshing = true;
    _failure = null;
    _completed = 0;
    _total = audios.length;
    final operation = Completer<void>();
    _pending = operation.future;
    // Reserve single-flight ownership before invoking a scanner: an injected
    // scanner may fail synchronously, without reaching its first await.
    final capture =
        _capture(audios, trackIds, playbackData, capturedAt, revision, warning);
    if (_refreshing) notifyListeners();
    unawaited(capture.then<void>((_) => operation.complete()));
    return operation.future;
  }

  Future<(PersonalOrganizationSummary?, Object?)> _capturePersonal(
      List<String> trackIds) async {
    try {
      final reading = _readPersonal();
      // A synchronous injected snapshot must be projected before yielding;
      // neither mutable Audio identities nor later tag edits can enter it.
      final personal = reading is Future<Map<String, PersonalTrack>>
          ? await reading
          : reading;
      return (
        PersonalOrganizationSummary.fromTrackIds(
            trackIds: trackIds, personal: personal),
        null
      );
    } catch (error) {
      return (null, error);
    }
  }

  Future<void> _capture(
      List<Audio> audios,
      List<String> trackIds,
      Map<String, Object?> playbackData,
      DateTime capturedAt,
      int revision,
      String? warning) async {
    try {
      final libraryReading = _scanner.scan(audios,
          isCancelled: () => _disposed,
          onProgress: (completed, total) {
            if (_disposed) return;
            _completed = completed;
            _total = total;
            notifyListeners();
          });
      final personalReading = _capturePersonal(trackIds);
      final library = await libraryReading;
      final (personalSummary, personalWarning) = await personalReading;
      if (_disposed) return;
      _snapshot = StatisticsDisplaySnapshot._(
          playbackData: playbackData,
          library: library,
          capturedAt: capturedAt,
          libraryRevision: revision,
          storageWarning: warning,
          personalSummary: personalSummary,
          personalWarning: personalWarning);
    } on LibraryScanCancelled {
      // Session disposal invalidates an in-flight capture, never a page exit.
    } catch (error) {
      if (!_disposed) _failure = error;
    } finally {
      if (!_disposed) {
        _refreshing = false;
        _pending = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
