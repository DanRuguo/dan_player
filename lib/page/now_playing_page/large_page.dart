part of 'page.dart';

class _NowPlayingPage_Large extends StatelessWidget {
  const _NowPlayingPage_Large();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    const spacer = SizedBox(width: 8.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32.0, 8.0, 32.0, 12.0),
      child: Column(
        children: [
          Expanded(
            child: AppEntrance(
              identity: 'now-playing-display',
              child: Row(
                children: [
                  const Expanded(child: _NowPlayingInfo()),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: NOW_PLAYING_VIEW_MODE,
                      builder: (context, value, _) => AnimatedSwitcher(
                        duration: AppMotion.standard,
                        child: switch (value) {
                          NowPlayingViewMode.onlyMain =>
                            const VerticalLyricView(),
                          NowPlayingViewMode.withLyric =>
                            const VerticalLyricView(),
                          NowPlayingViewMode.withPlaylist =>
                            const CurrentPlaylistView(),
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16.0),
          const QueueStopStatus(),
          const AppEntrance(
            identity: 'now-playing-slider',
            order: 1,
            child: SpectrumProgressSection(
              spectrum: FullWidthSpectrum(height: 32),
              progress: _NowPlayingSlider(),
            ),
          ),
          const AppEntrance(
            identity: 'now-playing-controls',
            order: 2,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppPlaybackModeControls(plain: true),
                        spacer,
                        _NowPlayingVolDspSlider(),
                        spacer,
                        PlaybackRateButton(),
                      ],
                    ),
                  ),
                  _NowPlayingMainControls(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _NowPlayingLargeViewSwitch(),
                        spacer,
                        _DesktopLyricSwitch(),
                        spacer,
                        _NowPlayingCommentsAction(),
                        spacer,
                        _NowPlayingMoreAction(),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 切换视图：lyric / playlist
class _NowPlayingLargeViewSwitch extends StatelessWidget {
  const _NowPlayingLargeViewSwitch();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder(
      valueListenable: NOW_PLAYING_VIEW_MODE,
      builder: (context, value, _) => IconButton(
        tooltip: switch (value) {
          NowPlayingViewMode.withPlaylist => ui("歌词"),
          _ => ui("播放列表"),
        },
        onPressed: () {
          if (value == NowPlayingViewMode.onlyMain ||
              value == NowPlayingViewMode.withLyric) {
            NOW_PLAYING_VIEW_MODE.value = NowPlayingViewMode.withPlaylist;
            AppPreference.instance.nowPlayingPagePref.nowPlayingViewMode =
                NowPlayingViewMode.withPlaylist;
          } else {
            NOW_PLAYING_VIEW_MODE.value = NowPlayingViewMode.withLyric;
            AppPreference.instance.nowPlayingPagePref.nowPlayingViewMode =
                NowPlayingViewMode.withLyric;
          }
        },
        icon: Icon(
          switch (value) {
            NowPlayingViewMode.withPlaylist => Symbols.lyrics,
            _ => Symbols.queue_music,
          },
        ),
        color: scheme.primary,
      ),
    );
  }
}
