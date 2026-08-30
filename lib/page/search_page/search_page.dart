import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class UnionSearchResult {
  String query;

  List<Audio> audios = [];
  List<Artist> artists = [];
  List<Album> album = [];
  late Future<OnlineSearchResponse> online;

  UnionSearchResult(this.query);

  static UnionSearchResult search(String query) {
    final result = UnionSearchResult(query);
    final index = AudioSearchIndex.instance..ensureBuiltSync();
    result.audios = index.searchAudios(query);
    result.artists = index.searchArtists(query);
    result.album = index.searchAlbums(query);
    result.online = OnlineMusicService.instance.search(query);
    return result;
  }
}

final SEARCH_BAR_KEY = GlobalKey();

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Transform.translate(
            offset: const Offset(0, -40.0),
            child: AppEntrance(
              identity: 'search-form',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ui("搜索"),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Padding(padding: EdgeInsets.only(bottom: 32.0)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400.0),
                    child: Focus(
                      onFocusChange: HotkeysHelper.onFocusChanges,
                      child: Hero(
                        tag: SEARCH_BAR_KEY,
                        child: TextField(
                          autofocus: true,
                          decoration: InputDecoration(
                            suffixIcon: const Padding(
                              padding: EdgeInsets.only(right: 12.0),
                              child: Icon(Symbols.search),
                            ),
                            hintText: ui("搜索本地曲库和联网音乐"),
                            border: AppShape.inputBorder,
                          ),

                          /// when 'enter' is pressed
                          onSubmitted: (String query) {
                            if (query.trim().isEmpty) return;
                            context.push(
                              app_paths.SEARCH_RESULT_PAGE,
                              extra: UnionSearchResult.search(query),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
