import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/playback_service.dart';

class PlayService {
  late final playbackService = PlaybackService(this);
  late final lyricService = LyricService(this);
  late final desktopLyricService = DesktopLyricService(this);

  PlayService._();

  static PlayService? _instance;
  static bool get isInitialized => _instance != null;

  static PlayService get instance {
    _instance ??= PlayService._();
    return _instance!;
  }

  Future<void> close() async {
    desktopLyricService.killDesktopLyric();
    await playbackService.close();
  }
}
