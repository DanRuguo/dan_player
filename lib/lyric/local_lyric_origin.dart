import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';

// Weak provenance does not retain lyrics or create a second document/cache.
final _origins = Expando<String>('discovered local lyric source');
bool isDiscoveredLocalLyric(Lyric lyric) =>
    _origins[lyric] != null ||
    (lyric is Lrc && lyric.source == LrcSource.local);
String? localLyricOrigin(Lyric lyric) => _origins[lyric];
void markDiscoveredLocalLyric(Lyric lyric, String origin) =>
    _origins[lyric] = origin;
