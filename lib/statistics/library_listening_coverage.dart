/// Listening history projected onto the distinct playback identities present
/// in one library capture. It never changes or infers ownership of old records.
class LibraryListeningCoverage {
  const LibraryListeningCoverage({
    required this.totalTracks,
    required this.recordedTracks,
    required this.uncertainTracks,
    required this.legacyUnassignedRecords,
  });

  final int totalTracks;
  final int recordedTracks;
  final int uncertainTracks;
  final int legacyUnassignedRecords;

  int get withoutRecordTracks => totalTracks - recordedTracks - uncertainTracks;
  double get recordedFraction =>
      totalTracks == 0 ? 0 : recordedTracks / totalTracks;

  factory LibraryListeningCoverage.capture({
    required Iterable<String> trackIds,
    required Map<String, Object?> playbackData,
  }) {
    final current = trackIds.toSet();
    final recorded = <String>{};
    final uncertain = <String>{};
    var unassigned = 0;
    for (final record in (playbackData['tracks'] as List? ?? const [])) {
      if (record is! Map) continue;
      // Imported history may retain listening time without a start count.
      final hasHistory = const [
        'playCount',
        'listenMilliseconds',
        'completedCount',
        'skippedCount',
        'lastPlayedAt',
      ].any((field) => (record[field] as num? ?? 0) > 0);
      if (!hasHistory) continue;
      if (record['legacyUnassigned'] == true) {
        unassigned++;
        for (final id in (record['candidateTrackIds'] as List? ?? const [])) {
          if (id is String && current.contains(id)) uncertain.add(id);
        }
      } else {
        final id = record['id'];
        if (id is String && current.contains(id)) recorded.add(id);
      }
    }
    // A new, clearly attributed play resolves coverage for that song without
    // assigning any of the ambiguous historical totals to it.
    uncertain.removeAll(recorded);
    return LibraryListeningCoverage(
      totalTracks: current.length,
      recordedTracks: recorded.length,
      uncertainTracks: uncertain.length,
      legacyUnassignedRecords: unassigned,
    );
  }
}
