import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Translate category UI without changing stored group identities or tags.
String categoryDisplayTitle(MusicCategoryGroup group) => group.isUnknown ||
        group.kind == MusicCategoryKind.bitrate ||
        group.kind == MusicCategoryKind.duration ||
        group.kind == MusicCategoryKind.language ||
        group.kind == MusicCategoryKind.source
    ? ui(group.title)
    : group.title;

String categorySourceSummary(MusicCategoryGroup group) => [
      if (group.localCount > 0) ui('本地 {0}', [group.localCount]),
      if (group.onlineCount > 0) ui('联网 {0}', [group.onlineCount]),
    ].join(' · ');

String categoryEvidenceSummary(MusicCategoryGroup group) => [
      for (final evidence in ClassificationEvidence.values)
        if ((group.evidenceCounts[evidence] ?? 0) > 0)
          '${ui(evidence.label)} ${group.evidenceCounts[evidence]}',
    ].join(' · ');
