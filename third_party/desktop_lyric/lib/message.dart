// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';

import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

String getMessageTypeName<T extends Message>() => T.toString();

abstract class Message {
  const Message();

  Map<String, dynamic> _toJson();

  String buildMessageJson() => "${json.encode({
            "type": runtimeType.toString(),
            "message": _toJson(),
          })}\n";
}

@JsonEnum(valueField: "code")
enum ControlEvent {
  pause(0),
  start(1),
  previousAudio(2),
  nextAudio(3),
  lock(4),
  close(5);

  const ControlEvent(this.code);
  final int code;
}

@JsonSerializable()
class InitArgsMessage {
  final bool isPlaying;

  /// now playing
  final String title;

  /// now playing
  final String artist;

  /// now playing
  final String album;

  final bool darkMode;

  /// theme
  final int primary;

  /// theme
  final int surfaceContainer;

  /// theme
  final int onSurface;

  final bool vertical;
  final double playbackRate;
  final String language;
  @JsonKey(fromJson: DesktopLyricAppearance.fromJson)
  final DesktopLyricAppearance appearance;

  const InitArgsMessage(this.isPlaying, this.title, this.artist, this.album,
      this.darkMode, this.primary, this.surfaceContainer, this.onSurface,
      {this.vertical = false,
      this.playbackRate = 1.0,
      this.language = 'zh',
      this.appearance = DesktopLyricAppearance.defaults});

  factory InitArgsMessage.fromJson(Map<String, dynamic> json) =>
      _$InitArgsMessageFromJson(json);

  Map<String, dynamic> toJson() => _$InitArgsMessageToJson(this);
}

/// Main player -> helper; old helpers safely ignore this additive message.
class UiLanguageMessage extends Message {
  const UiLanguageMessage(this.language);
  final String language;
  @override
  Map<String, dynamic> _toJson() => {'language': language};
}

/// desktop lyric -> player
@JsonSerializable()
class ControlEventMessage extends Message {
  final ControlEvent event;

  const ControlEventMessage(this.event);

  factory ControlEventMessage.fromJson(Map<String, dynamic> json) =>
      _$ControlEventMessageFromJson(json);

  @override
  Map<String, dynamic> _toJson() => _$ControlEventMessageToJson(this);
}

/// desktop lyric -> player
@JsonSerializable()
class PreferenceChangedMessage extends Message {
  final int primary;
  final int surfaceContainer;
  final int onSurface;

  const PreferenceChangedMessage(
    this.primary,
    this.surfaceContainer,
    this.onSurface,
  );

  factory PreferenceChangedMessage.fromJson(Map<String, dynamic> json) =>
      _$PreferenceChangedMessageFromJson(json);

  @override
  Map<String, dynamic> _toJson() => _$PreferenceChangedMessageToJson(this);
}

/// player -> desktop lyric
@JsonSerializable()
class PlayerStateChangedMessage extends Message {
  final bool playing;

  const PlayerStateChangedMessage(this.playing);

  factory PlayerStateChangedMessage.fromJson(Map<String, dynamic> json) =>
      _$PlayerStateChangedMessageFromJson(json);

  @override
  Map<String, dynamic> _toJson() => _$PlayerStateChangedMessageToJson(this);
}

/// player -> desktop lyric
@JsonSerializable()
class NowPlayingChangedMessage extends Message {
  final String title;
  final String artist;
  final String album;

  const NowPlayingChangedMessage(
    this.title,
    this.artist,
    this.album,
  );

  factory NowPlayingChangedMessage.fromJson(Map<String, dynamic> json) =>
      _$NowPlayingChangedMessageFromJson(json);

  @override
  Map<String, dynamic> _toJson() => _$NowPlayingChangedMessageToJson(this);
}

/// player -> desktop lyric
@JsonSerializable()
class LyricLineChangedMessage extends Message {
  final String content;
  final String? translation;
  final Duration length;

  const LyricLineChangedMessage(this.content, this.length, [this.translation]);

  factory LyricLineChangedMessage.fromJson(Map<String, dynamic> json) =>
      _$LyricLineChangedMessageFromJson(json);

  @override
  Map<String, dynamic> _toJson() => _$LyricLineChangedMessageToJson(this);
}

/// A word and its absolute playback timing used by the richer desktop lyric
/// renderer. Keeping this as a plain value object preserves compatibility with
/// older desktop lyric binaries, which simply ignore the newer message type.
class DesktopLyricWord {
  final int startMilliseconds;
  final int lengthMilliseconds;
  final String content;

  const DesktopLyricWord(
    this.startMilliseconds,
    this.lengthMilliseconds,
    this.content,
  );

  factory DesktopLyricWord.fromJson(Map<String, dynamic> json) {
    return DesktopLyricWord(
      (json['startMilliseconds'] as num?)?.toInt() ?? 0,
      (json['lengthMilliseconds'] as num?)?.toInt() ?? 0,
      json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'startMilliseconds': startMilliseconds,
        'lengthMilliseconds': lengthMilliseconds,
        'content': content,
      };
}

/// Periodic playback clock correction for desktop lyrics.
///
/// [sequence] identifies the current song. The desktop process discards an
/// older sequence so a late lyric lookup can never overwrite a newer song.
class PlaybackTimelineMessage extends Message {
  final int sequence;
  final int positionMilliseconds;
  final bool playing;
  final double playbackRate;

  const PlaybackTimelineMessage(
      this.sequence, this.positionMilliseconds, this.playing,
      {this.playbackRate = 1.0});

  factory PlaybackTimelineMessage.fromJson(Map<String, dynamic> json) {
    return PlaybackTimelineMessage(
      (json['sequence'] as num?)?.toInt() ?? 0,
      (json['positionMilliseconds'] as num?)?.toInt() ?? 0,
      json['playing'] as bool? ?? false,
      playbackRate: safeDesktopPlaybackRate(json['playbackRate']),
    );
  }

  @override
  Map<String, dynamic> _toJson() => <String, dynamic>{
        'sequence': sequence,
        'positionMilliseconds': positionMilliseconds,
        'playing': playing,
        'playbackRate': safeDesktopPlaybackRate(playbackRate),
      };
}

/// Old senders omit the multiplier. Reject invalid values rather than allowing
/// NaN, negative clocks or unbounded elapsed-time extrapolation.
double safeDesktopPlaybackRate(Object? value) =>
    value is num && value.isFinite ? value.toDouble().clamp(.5, 2.0) : 1.0;

/// Direction is independent of song/position so changing it never resets the
/// lyric clock. New messages are ignored by older desktop lyric components.
class DesktopLyricDisplayMessage extends Message {
  const DesktopLyricDisplayMessage({this.vertical = false});

  final bool vertical;

  factory DesktopLyricDisplayMessage.fromJson(Map<String, dynamic> json) =>
      DesktopLyricDisplayMessage(vertical: json['vertical'] == true);

  @override
  Map<String, dynamic> _toJson() => {'vertical': vertical};
}

/// desktop lyric -> player. The player persists the chosen orientation and
/// sends its canonical setting back, without touching playback or lyric data.
class DesktopLyricDisplayChangedMessage extends Message {
  const DesktopLyricDisplayChangedMessage({required this.vertical});

  final bool vertical;

  factory DesktopLyricDisplayChangedMessage.fromJson(
          Map<String, dynamic> json) =>
      DesktopLyricDisplayChangedMessage(vertical: json['vertical'] == true);

  @override
  Map<String, dynamic> _toJson() => {'vertical': vertical};
}

/// Canonical player snapshot; revision prevents a slow pipe echo from undoing
/// newer slider edits in the same helper process.
class DesktopLyricAppearanceMessage extends Message {
  const DesktopLyricAppearanceMessage(this.appearance, {this.revision = 0});
  final DesktopLyricAppearance appearance;
  final int revision;
  factory DesktopLyricAppearanceMessage.fromJson(Map<String, dynamic> json) {
    final value = DesktopLyricAppearance.tryFromJson(json['appearance']);
    final revision = json['revision'];
    if (value == null || revision is! int || revision < 0) {
      throw const FormatException('Invalid desktop lyric appearance snapshot');
    }
    return DesktopLyricAppearanceMessage(value, revision: revision);
  }
  @override
  Map<String, dynamic> _toJson() =>
      {'appearance': appearance.toJson(), 'revision': revision};
}

/// Helper -> player. The player alone persists the snapshot.
class DesktopLyricAppearanceChangedMessage
    extends DesktopLyricAppearanceMessage {
  const DesktopLyricAppearanceChangedMessage(super.appearance,
      {required super.revision});
  factory DesktopLyricAppearanceChangedMessage.fromJson(
      Map<String, dynamic> json) {
    final value = DesktopLyricAppearanceMessage.fromJson(json);
    return DesktopLyricAppearanceChangedMessage(value.appearance,
        revision: value.revision);
  }
}

class DesktopLyricAppearanceSavedMessage extends Message {
  const DesktopLyricAppearanceSavedMessage(
      {required this.revision, required this.saved});
  final int revision;
  final bool saved;
  factory DesktopLyricAppearanceSavedMessage.fromJson(
      Map<String, dynamic> json) {
    if (json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        json['saved'] is! bool) {
      throw const FormatException('Invalid appearance save result');
    }
    return DesktopLyricAppearanceSavedMessage(
        revision: json['revision'] as int, saved: json['saved'] as bool);
  }
  @override
  Map<String, dynamic> _toJson() => {'revision': revision, 'saved': saved};
}

/// Full current-line snapshot for line transitions and word-level highlighting.
class LyricLineTimelineMessage extends Message {
  final int sequence;
  final int lineIndex;
  final int startMilliseconds;
  final int lengthMilliseconds;
  final String content;
  final String? translation;
  final List<DesktopLyricWord> words;

  const LyricLineTimelineMessage({
    required this.sequence,
    required this.lineIndex,
    required this.startMilliseconds,
    required this.lengthMilliseconds,
    required this.content,
    required this.translation,
    required this.words,
  });

  factory LyricLineTimelineMessage.fromJson(Map<String, dynamic> json) {
    final rawWords = json['words'];
    return LyricLineTimelineMessage(
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      lineIndex: (json['lineIndex'] as num?)?.toInt() ?? -1,
      startMilliseconds: (json['startMilliseconds'] as num?)?.toInt() ?? 0,
      lengthMilliseconds: (json['lengthMilliseconds'] as num?)?.toInt() ?? 0,
      content: json['content'] as String? ?? '',
      translation: json['translation'] as String?,
      words: rawWords is List
          ? rawWords
              .whereType<Map>()
              .map(
                (word) => DesktopLyricWord.fromJson(
                  Map<String, dynamic>.from(word),
                ),
              )
              .toList(growable: false)
          : const <DesktopLyricWord>[],
    );
  }

  @override
  Map<String, dynamic> _toJson() => <String, dynamic>{
        'sequence': sequence,
        'lineIndex': lineIndex,
        'startMilliseconds': startMilliseconds,
        'lengthMilliseconds': lengthMilliseconds,
        'content': content,
        'translation': translation,
        'words': words.map((word) => word.toJson()).toList(growable: false),
      };
}

/// player -> desktop lyric
@JsonSerializable()
class ThemeModeChangedMessage extends Message {
  final bool darkMode;

  const ThemeModeChangedMessage(this.darkMode);

  factory ThemeModeChangedMessage.fromJson(Map<String, dynamic> json) =>
      _$ThemeModeChangedMessageFromJson(json);

  @override
  Map<String, dynamic> _toJson() => _$ThemeModeChangedMessageToJson(this);
}

/// player -> desktop lyric
@JsonSerializable()
class ThemeChangedMessage extends Message {
  final int primary;
  final int surfaceContainer;
  final int onSurface;

  const ThemeChangedMessage(
    this.primary,
    this.surfaceContainer,
    this.onSurface,
  );

  factory ThemeChangedMessage.fromJson(Map<String, dynamic> json) =>
      _$ThemeChangedMessageFromJson(json);

  @override
  Map<String, dynamic> _toJson() => _$ThemeChangedMessageToJson(this);
}

/// player -> desktop lyric
@JsonSerializable()
class UnlockMessage extends Message {
  const UnlockMessage();

  factory UnlockMessage.fromJson(Map<String, dynamic> json) =>
      _$UnlockMessageFromJson(json);

  @override
  Map<String, dynamic> _toJson() => _$UnlockMessageToJson(this);
}

// abstract class DesktopLyricMessage {
//   DesktopLyricMessage();

//   Map toMap() => {"type": "DesktopLyricMessage"};
// }

// enum PlayerAction {
//   /// 暂停，也表示歌曲暂停播放的状态。可以由播放器发送到桌面歌词，也可以反过来。
//   PAUSE,

//   /// 播放（resume），也表示歌曲播放中的状态。可以由播放器发送到桌面歌词，也可以反过来。
//   START,

//   /// 上一曲。只可以由桌面歌词发送到播放器。
//   PREVIOUS_AUDIO,

//   /// 下一曲。只可以由桌面歌词发送到播放器
//   NEXT_AUDIO,

//   /// 关闭桌面歌词。只可以由桌面歌词发送到播放器
//   CLOSE_DESKTOP_LYRIC;

//   static PlayerAction? fromName(String name) {
//     for (var item in PlayerAction.values) {
//       if (item.name == name) return item;
//     }
//     return null;
//   }
// }

// /// 播放器行为。可以由播放器发送到桌面歌词，也可以反过来。
// ///
// /// 当播放器每一次暂停或者开始播放歌曲时，都应该发送此消息。
// ///
// /// 示例如下，如果这个消息由播放器发送给桌面歌词，就是更新桌面歌词的状态为暂停；
// /// 如果是由桌面歌词发送给播放器，就是请求播放器暂停音乐。
// /// ```json
// /// {
// ///   "type": "PlayerActionMessage",
// ///   "action": "PAUSE"
// /// }
// /// ```
// class PlayerActionMessage extends DesktopLyricMessage {
//   final PlayerAction? action;

//   PlayerActionMessage({required this.action});

//   @override
//   Map toMap() => {
//         "type": "PlayerActionMessage",
//         "action": action?.name,
//       };

//   @override
//   String toString() => json.encode(toMap());

//   factory PlayerActionMessage.fromMap(Map map) => PlayerActionMessage(
//         action: PlayerAction.fromName(map["action"]),
//       );
// }

// /// 主题模式更新信息。只可以由播放器发送到桌面歌词。
// ///
// /// 可以在播放器启用夜间模式时通知桌面歌词切换到夜间模式。
// ///
// /// 示例如下，这样要求桌面歌词切换到夜间模式。
// /// ```json
// /// {
// ///   "type": "ThemeModeChangedMessage",
// ///   "isDarkMode": true
// /// }
// /// ```
// class ThemeModeChangedMessage extends DesktopLyricMessage {
//   final bool isDarkMode;

//   ThemeModeChangedMessage({required this.isDarkMode});

//   @override
//   Map toMap() => {
//         "type": "ThemeModeChangedMessage",
//         "isDarkMode": isDarkMode,
//       };
//   @override
//   String toString() => json.encode(toMap());

//   factory ThemeModeChangedMessage.fromMap(Map map) => ThemeModeChangedMessage(
//         isDarkMode: map["isDarkMode"],
//       );
// }

// /// 主题更新信息。只可以由播放器发送到桌面歌词。
// ///
// /// primary: 用于歌曲信息和歌词文本
// /// surfaceContainer: 用于鼠标悬停在桌面歌词上时的背景颜色
// /// onSurface: 用于控件颜色（鼠标悬停在桌面歌词上时的控件）
// ///
// /// 如果播放器可以更改主题色，可以通过这个消息让桌面歌词的主题与之一致。
// ///
// /// 示例如下，这样要求桌面歌词使用指定主题。
// ///
// /// ```json
// /// {
// ///   "type": "ThemeChangedMessage",
// ///   "primary": 0xFFFF9000,
// ///   "surfaceContainer": 0xFFFF9000,
// ///   "onSurface": 0xFFFF9000,
// /// }
// /// ```
// /// For example, to get a fully opaque orange, you would use const Color(0xFFFF9000)
// /// (FF for the alpha, FF for the red, 90 for the green, and 00 for the blue)。
// ///
// /// 这里应该要把 0xFFFF9000 当作 int 来构造 json
// class ThemeChangedMessage extends DesktopLyricMessage {
//   final Color primary;
//   final Color surfaceContainer;
//   final Color onSurface;

//   ThemeChangedMessage({
//     required this.primary,
//     required this.surfaceContainer,
//     required this.onSurface,
//   });

//   ThemeChangedMessage.fromColorScheme(ColorScheme scheme)
//       : primary = scheme.primary,
//         surfaceContainer = scheme.surfaceContainer,
//         onSurface = scheme.onSurface;

//   @override
//   Map toMap() => {
//         "type": "ThemeChangedMessage",
//         "primary": primary.value,
//         "surfaceContainer": surfaceContainer.value,
//         "onSurface": onSurface.value,
//       };
//   @override
//   String toString() => json.encode(toMap());

//   factory ThemeChangedMessage.fromMap(Map map) => ThemeChangedMessage(
//         primary: Color(map["primary"]),
//         surfaceContainer: Color(map["surfaceContainer"]),
//         onSurface: Color(map["onSurface"]),
//       );
// }

// /// 正在播放曲目更新信息。只可以由播放器发送到桌面歌词。
// ///
// /// 在每次开始播放曲目时发送。
// ///
// /// 示例如下，这样要求桌面歌词显示指定的正在播放曲目信息。
// /// ```json
// /// {
// ///   "type": "NowPlayingChangedMessage",
// ///   "title": "title",
// ///   "artist": "artist",
// ///   "album": "album",
// /// }
// /// ```
// class NowPlayingChangedMessage extends DesktopLyricMessage {
//   final String title;
//   final String artist;
//   final String album;

//   NowPlayingChangedMessage({
//     required this.title,
//     required this.artist,
//     required this.album,
//   });

//   @override
//   Map toMap() => {
//         "type": "NowPlayingChangedMessage",
//         "title": title,
//         "artist": artist,
//         "album": album,
//       };
//   @override
//   String toString() => json.encode(toMap());

//   factory NowPlayingChangedMessage.fromMap(Map map) => NowPlayingChangedMessage(
//       title: map["title"], artist: map["artist"], album: map["album"]);
// }

// /// 当前歌词行更新信息。只可以由播放器发送到桌面歌词。
// ///
// /// content: 歌词内容，String
// /// translation: 翻译，String（也可为 null）
// /// length: 当前行持续时间（以 millisecond 计）。如果指定，桌面歌词会在歌词长度超出区域时在 length 指定时间内滚动展示整句歌词。
// ///
// /// 在当前歌词行更新时发送。
// ///
// /// 示例如下，这样要求桌面歌词显示指定的歌词。
// /// ```json
// /// {
// ///   "type": "LyricLineMessage",
// ///   "content": "宙舞う埃がキラキラ反射してる",
// ///   "translation": "宛若在空中飞舞般 反射着光芒" / null,
// ///   "length": 11890,
// /// }
// /// ```
// class LyricLineMessage extends DesktopLyricMessage {
//   final String content;
//   final String? translation;
//   final Duration length;
//   LyricLineMessage({
//     required this.content,
//     this.translation,
//     required this.length,
//   });
//   @override
//   Map toMap() => {
//         "type": "LyricLineMessage",
//         "content": content,
//         "translation": translation,
//         "length": length.inMilliseconds,
//       };
//   @override
//   String toString() => json.encode(toMap());

//   factory LyricLineMessage.fromMap(Map map) => LyricLineMessage(
//         content: map["content"],
//         translation: map["translation"],
//         length: Duration(milliseconds: map["length"]),
//       );
// }

/// Main player -> lyric helper; also forwarded to its appearance engine.
class FrameRateMessage extends Message {
  const FrameRateMessage(this.preference);
  final Map<String, Object> preference;
  @override
  Map<String, dynamic> _toJson() => preference;
}
