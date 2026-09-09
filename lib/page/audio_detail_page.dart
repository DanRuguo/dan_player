import 'package:dan_player/component/personal_library_dialog.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/album_tile.dart';
import 'package:dan_player/component/artist_tile.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/artwork_backdrop.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/component/audio_metadata_dialog.dart';
import 'package:dan_player/component/full_width_spectrum.dart';
import 'package:dan_player/component/lyric_editor_dialog.dart';
import 'package:dan_player/component/online_source_display.dart';
import 'package:dan_player/component/playback_diagnostics_panel.dart';
import 'package:dan_player/component/song_comments_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/src/rust/api/utils.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/utils.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class AudioDetailPage extends StatefulWidget {
  const AudioDetailPage({super.key, required this.audio});

  final Audio audio;

  @override
  State<AudioDetailPage> createState() => _AudioDetailPageState();
}

class _AudioDetailPageState extends State<AudioDetailPage> {
  Audio get audio => widget.audio;
  int _metadataRevision = 0;

  Future<void> _toggleLibrary() async {
    try {
      if (OnlineLibrary.instance.contains(audio)) {
        await OnlineLibrary.instance.remove(audio);
        showTextOnSnackBar("已从总乐库移除");
      } else {
        await OnlineLibrary.instance.add(audio);
        showTextOnSnackBar("已加入总乐库");
      }
      if (mounted) setState(() {});
    } catch (error) {
      showTextOnSnackBar("更新总乐库失败：{0}", arguments: [error]);
    }
  }

  Future<void> _download() async {
    final service = OnlineMusicService.instance;
    if (!service.canDownload(audio)) {
      showTextOnSnackBar(
          service.downloadUnavailableReason(audio) ?? "当前来源不支持下载");
      return;
    }
    final picker = SaveFilePicker()
      ..title = ui("下载联网音乐")
      ..fileName = OnlineMusicService.suggestedFileName(audio)
      ..defaultExtension = "mp3"
      ..filterSpecification = {
        ui("音频文件"): "*.mp3;*.m4a;*.flac;*.ogg",
        ui("所有文件"): "*.*",
      };
    final file = picker.getFile();
    if (file == null) return;
    showTextOnSnackBar("正在下载 {0}…", arguments: [audio.title]);
    try {
      await OnlineMusicService.instance.download(audio, file);
      showTextOnSnackBar("下载完成：{0}", arguments: [file.path]);
    } on OnlineMusicException catch (error) {
      showTextOnSnackBar(error.message);
    }
  }

  Future<void> _editMetadata() async {
    if (await showEditAudioMetadataDialog(context, audio) && mounted) {
      setState(() => _metadataRevision++);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    // Capture mutable metadata values in the key so an edit to the same Audio
    // object still refreshes both images, including same-second cover changes.
    final artworkKey = (
      audio,
      audio.path,
      audio.modified,
      audio.artworkUrl,
      AudioLibrary.revision,
      _metadataRevision,
    );
    final artists = [
      for (final name in audio.splitedArtists)
        if (AudioLibrary.instance.artistCollection[name] != null)
          AudioLibrary.instance.artistCollection[name]!,
    ];
    final album = AudioLibrary.instance.albumCollection[audio.albumIdentity.id];
    final trackStats = PlaybackStatistics
        .instance.tracks[PlaybackStatistics.instance.identityFor(audio)];

    return AppEntranceScope(
      child: ArtworkBackdrop(
        artworkKey: artworkKey,
        loadArtwork: () => audio.mediumCover,
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 112.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 700;
                    final cover = AppEntrance(
                      identity: 'audio-detail-cover',
                      child: _DetailCover(
                        key: ValueKey(artworkKey),
                        audio: audio,
                        size: compact ? 180 : 240,
                      ),
                    );
                    final info = AppEntrance(
                      identity: 'audio-detail-info',
                      order: 1,
                      child: _HeroInfo(
                        audio: audio,
                        onEditMetadata: _editMetadata,
                        onEditLyric: () =>
                            showLyricEditorDialog(context, audio),
                        onToggleLibrary: _toggleLibrary,
                        onDownload: _download,
                      ),
                    );
                    return compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(child: cover),
                              const SizedBox(height: 20.0),
                              info,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              cover,
                              const SizedBox(width: 28.0),
                              Expanded(child: info),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 20.0),
                AppEntrance(
                  identity: 'audio-detail-spectrum',
                  order: 2,
                  child: _TrackSpectrum(audio: audio),
                ),
                const SizedBox(height: 20.0),
                LayoutBuilder(builder: (context, constraints) {
                  final specs = <Widget>[
                    _SpecCard(
                      icon: Symbols.schedule,
                      label: ui("时长"),
                      value: Duration(seconds: audio.duration).toStringHMMSS(),
                    ),
                    _SpecCard(
                      icon: Symbols.cloud,
                      label: ui("来源"),
                      value: audio.isOnline
                          ? onlineSourceDisplayLabel(
                              provider: audio.onlineProvider,
                              fallback: audio.sourceLabel,
                            )
                          : ui("本地文件"),
                    ),
                    if (audio.track > 0)
                      _SpecCard(
                        icon: Symbols.format_list_numbered,
                        label: ui("音轨"),
                        value: "${audio.track}",
                      ),
                    if (audio.bitrate != null)
                      _SpecCard(
                        icon: Symbols.speed,
                        label: ui("码率"),
                        value: "${audio.bitrate} kbps",
                      ),
                    if (audio.sampleRate != null)
                      _SpecCard(
                        icon: Symbols.graphic_eq,
                        label: ui("采样率"),
                        value: "${audio.sampleRate} Hz",
                      ),
                    if (trackStats != null)
                      _SpecCard(
                        icon: Symbols.play_circle,
                        label: ui("播放统计"),
                        value: ui("{0} 次 · {1}", [
                          trackStats.playCount,
                          Duration(milliseconds: trackStats.listenMilliseconds)
                              .toStringHMMSS(),
                        ]),
                      ),
                  ];
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  final columns = (constraints.maxWidth / (180 * scale))
                      .floor()
                      .clamp(1, specs.length);
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final spec in specs)
                      SizedBox(width: width, child: spec)
                  ]);
                }),
                const SizedBox(height: 24.0),
                PlaybackDiagnosticsPanel(audio: audio),
                const SizedBox(height: 16.0),
                LayoutBuilder(builder: (context, constraints) {
                  final related = <Widget>[
                    if (artists.isNotEmpty)
                      _DetailSection(
                        title: ui("艺术家"),
                        child: Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: [
                            for (final artist in artists)
                              SizedBox(
                                  width: 320,
                                  child: ArtistTile(artist: artist)),
                          ],
                        ),
                      )
                    else
                      _DetailSection(
                          title: ui("艺术家"), child: Text(audio.artist)),
                    if (album != null)
                      _DetailSection(
                          title: ui("专辑"), child: AlbumTile(album: album))
                    else
                      _DetailSection(title: ui("专辑"), child: Text(audio.album)),
                  ];
                  return constraints.maxWidth /
                              MediaQuery.textScalerOf(context).scale(1) >=
                          700
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Expanded(child: related[0]),
                              const SizedBox(width: 12),
                              Expanded(child: related[1])
                            ])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: related);
                }),
                if (audio.isOnline)
                  _DetailSection(
                    title: ui("联网标识"),
                    child: OnlineIdentitySummary(
                      provider: audio.onlineProvider ?? '',
                      id: audio.onlineId ?? '',
                    ),
                  )
                else ...[
                  _DetailSection(
                    title: ui("文件位置"),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(audio.localFilePath),
                        if (audio.cueTrack case final cue?) ...[
                          const SizedBox(height: 8),
                          Text(ui('CUE 分轨 · 第 {0} 轨 · 起点 {1} 秒', [
                            cue.number,
                            cue.startSeconds.toStringAsFixed(2)
                          ])),
                          SelectableText(cue.cuePath),
                        ],
                        const SizedBox(height: 8.0),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final result =
                                await showInExplorer(path: audio.localFilePath);
                            if (!result) showTextOnSnackBar("打开失败");
                          },
                          icon: const Icon(Symbols.folder_open),
                          label: Text(ui("在文件资源管理器中显示")),
                        ),
                      ],
                    ),
                  ),
                  _DetailSection(
                    title: ui("文件时间"),
                    child: Text(
                      ui("创建：{0}\n修改：{1}", [
                        DateTime.fromMillisecondsSinceEpoch(
                            audio.created * 1000),
                        DateTime.fromMillisecondsSinceEpoch(
                            audio.modified * 1000)
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailCover extends StatelessWidget {
  const _DetailCover({super.key, required this.audio, required this.size});
  final Audio audio;
  final double size;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: AppShape.surfaceRadius,
        color: scheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.22),
            blurRadius: 28.0,
            offset: const Offset(0, 14.0),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AudioArtwork(
        audio: audio,
        size: size,
        placeholder: Icon(Symbols.music_note, size: size * 0.45),
        loading: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({
    required this.audio,
    required this.onEditMetadata,
    required this.onEditLyric,
    required this.onToggleLibrary,
    required this.onDownload,
  });

  final Audio audio;
  final VoidCallback onEditMetadata;
  final VoidCallback onEditLyric;
  final VoidCallback onToggleLibrary;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final inLibrary = audio.isOnline && OnlineLibrary.instance.contains(audio);
    final canDownload = OnlineMusicService.instance.canDownload(audio);
    final downloadReason =
        OnlineMusicService.instance.downloadUnavailableReason(audio);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chip(
          avatar: Icon(audio.isOnline ? Symbols.cloud : Symbols.hard_drive,
              size: 18),
          label: Text(
            audio.isOnline
                ? ui("联网音乐 · {0}", [
                    onlineSourceDisplayLabel(
                      provider: audio.onlineProvider,
                      fallback: audio.sourceLabel,
                    )
                  ])
                : ui("本地音乐"),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10.0),
        Text(
          audio.displayTitle,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 6.0),
        Text(
          "${audio.artist} · ${audio.album}",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 18.0),
        Wrap(
          spacing: 10.0,
          runSpacing: 10.0,
          children: [
            FilledButton.icon(
              onPressed: () =>
                  PlayService.instance.playbackService.play(0, [audio]),
              icon: const Icon(Symbols.play_arrow),
              label: Text(ui("播放")),
            ),
            if (audio.isLocal) ...[
              if (audio.canEditLocalFile)
                OutlinedButton.icon(
                  onPressed: onEditMetadata,
                  icon: const Icon(Symbols.edit_note),
                  label: Text(ui("编辑信息")),
                ),
              if (audio.canEditLocalFile)
                OutlinedButton.icon(
                  onPressed: onEditLyric,
                  icon: const Icon(Symbols.lyrics),
                  label: Text(ui("编辑歌词")),
                ),
              OutlinedButton.icon(
                onPressed: () => showSongCommentsDialog(context, audio),
                icon: const Icon(Symbols.chat_bubble_outline),
                label: Text(ui("歌曲评论")),
              ),
              OutlinedButton.icon(
                onPressed: () => showPersonalTrackEditor(context, [audio]),
                icon: const Icon(Symbols.star),
                label: Text(ui("个人评分与标签")),
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: () => showSongCommentsDialog(context, audio),
                icon: const Icon(Symbols.chat_bubble_outline),
                label: Text(ui("歌曲评论")),
              ),
              OutlinedButton.icon(
                onPressed: () => showPersonalTrackEditor(context, [audio]),
                icon: const Icon(Symbols.star),
                label: Text(ui("个人评分与标签")),
              ),
              OutlinedButton.icon(
                onPressed: onToggleLibrary,
                icon: Icon(inLibrary
                    ? Symbols.library_add_check
                    : Symbols.library_add),
                label: Text(inLibrary ? ui("移出总乐库") : ui("加入总乐库")),
              ),
              Tooltip(
                message: canDownload
                    ? ui("保存到本地")
                    : ui(downloadReason ?? "当前来源不支持下载"),
                child: OutlinedButton.icon(
                  onPressed: canDownload ? onDownload : null,
                  icon: const Icon(Symbols.download),
                  label: Text(canDownload ? ui("下载") : ui("当前来源不可下载")),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _TrackSpectrum extends StatelessWidget {
  const _TrackSpectrum({required this.audio});
  final Audio audio;

  @override
  Widget build(BuildContext context) => PlaybackReadyBuilder(
      waitingBuilder: (context) => _content(context, false),
      readyBuilder: (context) {
        final playback = PlayService.instance.playbackService;
        return ListenableBuilder(
            listenable: playback,
            builder: (context, _) =>
                _content(context, playback.nowPlaying?.path == audio.path));
      });

  Widget _content(BuildContext context, bool active) {
    UiLanguageScope.watch(context);
    return AnimatedContainer(
        duration: AppMotion.emphasized,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: active ? .45 : .20),
            borderRadius: AppShape.surfaceRadius),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ui(active ? '实时频谱' : '播放这首歌以显示实时频谱')),
          if (active) ...[
            const SizedBox(height: 6),
            const FullWidthSpectrum(height: 64)
          ],
        ]));
  }
}

class _SpecCard extends StatelessWidget {
  const _SpecCard(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppEntrance(
      identity: ('audio-spec', label),
      order: 3,
      child: Container(
        constraints: const BoxConstraints(minWidth: 160, maxWidth: 320),
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: .6)),
          borderRadius: AppShape.controlRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10.0),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppEntrance(
      identity: ('audio-section', title),
      order: 4,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: AppShape.controlRadius,
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: .6))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8.0),
            child,
          ],
        ),
      ),
    );
  }
}
