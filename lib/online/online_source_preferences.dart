import 'package:flutter/foundation.dart';

/// Built-in providers only. Enabling a provider is a search-routing choice,
/// never permission to bypass its access restrictions or alter saved tracks.
enum OnlineMusicSource {
  qq('qq', 'QQ音乐', '该歌曲的下载地址当前不可用或需要登录'),
  netease('netease', '网易云音乐', '该歌曲的下载地址当前不可用或需要登录');

  const OnlineMusicSource(this.id, this.label, this.downloadUnavailableReason);

  final String id;
  final String label;
  final String downloadUnavailableReason;

  /// Allows a user-initiated attempt; the actual endpoint still decides
  /// whether this particular track is available anonymously.
  bool get supportsDownload => true;

  static OnlineMusicSource? fromId(String? id) {
    for (final source in values) {
      if (source.id == id) return source;
    }
    return null;
  }
}

const onlineSourcesDisabledMessage = '未启用联网歌源，请在设置开启';

@immutable
class OnlineSourcePreferences {
  const OnlineSourcePreferences({
    this.qqEnabled = true,
    this.neteaseEnabled = true,
  });

  final bool qqEnabled;
  final bool neteaseEnabled;

  bool isEnabled(OnlineMusicSource source) => switch (source) {
        OnlineMusicSource.qq => qqEnabled,
        OnlineMusicSource.netease => neteaseEnabled,
      };

  /// Keeps the existing merge order (QQ, then Netease), independently of the
  /// order in which the parallel requests happen to complete.
  List<OnlineMusicSource> get enabledSources => [
        for (final source in OnlineMusicSource.values)
          if (isEnabled(source)) source,
      ];

  bool get isEmpty => !qqEnabled && !neteaseEnabled;

  OnlineSourcePreferences withEnabled(OnlineMusicSource source, bool enabled) =>
      OnlineSourcePreferences(
        qqEnabled: source == OnlineMusicSource.qq ? enabled : qqEnabled,
        neteaseEnabled:
            source == OnlineMusicSource.netease ? enabled : neteaseEnabled,
      );

  /// `OnlineSources` is an allow-list of known provider IDs. Missing/invalid
  /// container values are legacy settings and retain the two-source default.
  /// An explicit empty list means all sources off, not "use defaults".
  List<String> toJson() => [for (final source in enabledSources) source.id];

  factory OnlineSourcePreferences.fromJson(Object? value) {
    if (value is! List) return const OnlineSourcePreferences();
    final ids = value.whereType<String>().toSet();
    return OnlineSourcePreferences(
      qqEnabled: ids.contains(OnlineMusicSource.qq.id),
      neteaseEnabled: ids.contains(OnlineMusicSource.netease.id),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OnlineSourcePreferences &&
      qqEnabled == other.qqEnabled &&
      neteaseEnabled == other.neteaseEnabled;

  @override
  int get hashCode => Object.hash(qqEnabled, neteaseEnabled);
}
