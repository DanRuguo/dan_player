import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/album_tile.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/artist_tile.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class SearchResultPage extends StatefulWidget {
  const SearchResultPage({super.key, required this.searchResult});

  final UnionSearchResult searchResult;

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  late UnionSearchResult searchResult = widget.searchResult;
  late final searchBarController = TextEditingController(
    text: widget.searchResult.query,
  );

  void _search(String query) {
    final value = query.trim();
    if (value.isEmpty) return;
    setState(() => searchResult = UnionSearchResult.search(value));
  }

  @override
  void dispose() {
    searchBarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: DefaultTabController(
          length: _SearchResultFilter.values.length,
          child: Column(
            children: [
              AppEntrance(
                identity: 'search-result-input',
                child: Focus(
                  onFocusChange: HotkeysHelper.onFocusChanges,
                  child: Hero(
                    tag: SEARCH_BAR_KEY,
                    child: TextField(
                      controller: searchBarController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        suffixIcon: const Padding(
                          padding: EdgeInsets.only(right: 12.0),
                          child: Icon(Symbols.search),
                        ),
                        hintText: ui("搜索本地曲库和联网音乐"),
                        border: AppShape.inputBorder,
                      ),
                      onSubmitted: _search,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8.0),
              AppEntrance(
                identity: 'search-result-tabs',
                order: 1,
                child: Material(
                  type: MaterialType.transparency,
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: _SearchResultFilter.values
                        .map((filter) => Tab(text: ui(filter.label)))
                        .toList(),
                  ),
                ),
              ),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: TabBarView(
                    children: [
                      for (final filter in _SearchResultFilter.values)
                        _SearchResultBody(
                          key: ValueKey("${searchResult.query}-${filter.name}"),
                          result: searchResult,
                          filter: filter,
                          retryOnline: () => _search(searchResult.query),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SearchResultFilter {
  all("所有"),
  library("总乐库"),
  online("联网"),
  artist("艺术家"),
  album("专辑");

  const _SearchResultFilter(this.label);
  final String label;
}

class _SearchResultBody extends StatelessWidget {
  const _SearchResultBody({
    super.key,
    required this.result,
    required this.filter,
    required this.retryOnline,
  });

  final UnionSearchResult result;
  final _SearchResultFilter filter;
  final VoidCallback retryOnline;

  SliverToBoxAdapter _header(BuildContext context, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 16.0, 8.0, 8.0),
        child: AppEntrance(
          identity: ('search-section', title),
          order: 2,
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _librarySlivers(BuildContext context, {bool showHeader = true}) {
    final tracks = result.audios;
    return [
      if (showHeader) _header(context, ui("总乐库")),
      if (tracks.isEmpty)
        SliverToBoxAdapter(
          child: _EmptyResult(label: ui("总乐库中没有匹配歌曲")),
        )
      else
        SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final item = tracks[index];
            return AudioTile(
              key: ValueKey(item.path),
              audioIndex: index,
              playlist: tracks,
              action: IconButton(
                tooltip: ui("在总乐库中定位"),
                onPressed: () {
                  context.push(app_paths.AUDIOS_PAGE, extra: item);
                },
                icon: const Icon(Symbols.location_on),
              ),
            );
          },
        ),
    ];
  }

  List<Widget> _artistSlivers(BuildContext context, {bool showHeader = true}) =>
      [
        if (showHeader) _header(context, ui("艺术家")),
        if (result.artists.isEmpty)
          SliverToBoxAdapter(
            child: _EmptyResult(label: ui("没有匹配艺术家")),
          )
        else
          SliverList.builder(
            itemCount: result.artists.length,
            itemBuilder: (context, index) => ArtistTile(
              key: ValueKey(result.artists[index].name),
              artist: result.artists[index],
            ),
          ),
      ];

  List<Widget> _albumSlivers(BuildContext context, {bool showHeader = true}) =>
      [
        if (showHeader) _header(context, ui("专辑")),
        if (result.album.isEmpty)
          SliverToBoxAdapter(
            child: _EmptyResult(label: ui("没有匹配专辑")),
          )
        else
          SliverList.builder(
            itemCount: result.album.length,
            itemBuilder: (context, index) => AlbumTile(
              key: ValueKey(result.album[index].name),
              album: result.album[index],
            ),
          ),
      ];

  SliverToBoxAdapter _onlineSliver(
    BuildContext context, {
    bool showHeader = true,
  }) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 16.0, 8.0, 8.0),
              child: AppEntrance(
                identity: 'search-online-title',
                order: 2,
                child: Text(
                  ui("联网音乐"),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          FutureBuilder<OnlineSearchResponse>(
            future: result.online,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _OnlineFailure(
                  message: snapshot.error.toString(),
                  retry: retryOnline,
                );
              }
              final response = snapshot.data!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 8.0),
                    child: Text(
                      ui("搜索已启用的联网歌源；播放能力由平台授权与接口可用性决定，当前不提供下载。"),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (response.failures.isNotEmpty)
                    _PartialFailure(failures: response.failures),
                  if (response.tracks.isEmpty)
                    _EmptyResult(label: ui("联网服务没有找到匹配歌曲"))
                  else
                    for (var i = 0; i < response.tracks.length; i++)
                      AudioTile(
                        key: ValueKey(response.tracks[i].path),
                        audioIndex: i,
                        playlist: response.tracks,
                      ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final slivers = <Widget>[];
    switch (filter) {
      case _SearchResultFilter.all:
        if (result.audios.isNotEmpty) slivers.addAll(_librarySlivers(context));
        slivers.add(_onlineSliver(context));
        if (result.artists.isNotEmpty) slivers.addAll(_artistSlivers(context));
        if (result.album.isNotEmpty) slivers.addAll(_albumSlivers(context));
        break;
      case _SearchResultFilter.library:
        slivers.addAll(_librarySlivers(context, showHeader: false));
        break;
      case _SearchResultFilter.online:
        slivers.add(_onlineSliver(context, showHeader: false));
        break;
      case _SearchResultFilter.artist:
        slivers.addAll(_artistSlivers(context, showHeader: false));
        break;
      case _SearchResultFilter.album:
        slivers.addAll(_albumSlivers(context, showHeader: false));
        break;
    }
    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 96.0)));
    return AppContentScrollbar(
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: slivers,
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppEntrance(
      identity: ('search-empty', label),
      order: 2,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _OnlineFailure extends StatelessWidget {
  const _OnlineFailure({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppEntrance(
      identity: 'search-online-failure',
      order: 2,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Icon(Symbols.cloud_off, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8.0),
            Text(ui("联网搜索失败：{0}", [message]), textAlign: TextAlign.center),
            const SizedBox(height: 12.0),
            OutlinedButton.icon(
              onPressed: retry,
              icon: const Icon(Symbols.refresh),
              label: Text(ui("重试")),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartialFailure extends StatelessWidget {
  const _PartialFailure({required this.failures});
  final Map<String, String> failures;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AppEntrance(
      identity: 'search-online-partial-failure',
      order: 2,
      child: Card.filled(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              const Icon(Symbols.warning),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  failures.entries
                      .map((entry) => "${entry.key}：${entry.value}")
                      .join("\n"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
