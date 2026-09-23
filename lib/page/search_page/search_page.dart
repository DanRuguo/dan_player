import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/library_search_field.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/now_playing_bar_metrics.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/search/search_history.dart';
import 'package:dan_player/page/search_page/search_history_capsules.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:desktop_lyric/ui_language.dart';

class UnionSearchResult {
  String query;

  List<Audio> audios = [];
  List<Artist> artists = [];
  List<Album> album = [];
  late Future<OnlineSearchResponse> _online;
  bool _onlineInitialized = false;
  final OnlineSearchCancellation onlineCancellation;

  Future<OnlineSearchResponse> get online => _online;
  set online(Future<OnlineSearchResponse> value) {
    _online = value;
    _onlineInitialized = true;
    // A disabled provider can fail before navigation's first frame attaches
    // FutureBuilder. Observe that branch now, while retaining the original
    // Future and its error for the results UI and retry affordance.
    value.ignore();
  }

  UnionSearchResult(
    this.query, {
    OnlineSearchCancellation? onlineCancellation,
  }) : onlineCancellation = onlineCancellation ?? OnlineSearchCancellation();

  void cancelOnlineSearch() {
    onlineCancellation.cancel();
    // A result can become stale between the local index await and attaching
    // its FutureBuilder. Observe its cancellation error in that narrow case.
    if (_onlineInitialized) _online.ignore();
  }

  /// Build local pinyin projections without monopolising the UI isolate.
  ///
  /// Refresh and deletion normally warm the index in the background, but a
  /// search submitted during that short window must not fall back to the
  /// synchronous builder and make the field/button look stuck.
  static Future<UnionSearchResult> search(
    String query, {
    OnlineSearchCancellation? onlineCancellation,
  }) async {
    final result = UnionSearchResult(
      query,
      onlineCancellation: onlineCancellation,
    );
    final index = AudioSearchIndex.instance;
    final local = await index.searchAll(query,
        checkCancelled: result.onlineCancellation.check);
    result.onlineCancellation.check();
    result.audios = local.audios;
    result.artists = local.artists;
    result.album = local.albums;
    // Avoid starting providers for an already cancelled local query. The
    // setter also observes failures that precede FutureBuilder's first frame.
    result.online = OnlineMusicService.instance.search(
      query,
      cancellation: result.onlineCancellation,
    );
    return result;
  }
}

final SEARCH_BAR_KEY = GlobalKey();

typedef LibrarySearch = Future<UnionSearchResult> Function(
  String query, {
  OnlineSearchCancellation? onlineCancellation,
});

class SearchPage extends StatefulWidget {
  const SearchPage(
      {super.key, this.search = UnionSearchResult.search, this.history});

  final LibrarySearch search;
  final SearchHistoryStore? history;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  OnlineSearchCancellation? _cancellation;
  String? _pendingQuery;
  String? _error;
  int _request = 0;
  late final SearchHistoryStore _history =
      widget.history ?? SearchHistoryStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_history.load().catchError((Object error, StackTrace trace) {
      LOGGER.w('[load search history] $error', stackTrace: trace);
    }));
  }

  void _changed(String value) {
    if (value.trim() != _pendingQuery) {
      _request++;
      _cancellation?.cancel();
      _cancellation = null;
      _pendingQuery = null;
    }
    setState(() => _error = null);
  }

  Future<void> _search(String query) async {
    final value = query.trim();
    if (value.isEmpty || value == _pendingQuery) return;
    final request = ++_request;
    _cancellation?.cancel();
    final cancellation = OnlineSearchCancellation();
    _cancellation = cancellation;
    setState(() {
      _pendingQuery = value;
      _error = null;
    });
    unawaited(rememberSearch(context, _history, value));
    try {
      final result =
          await widget.search(value, onlineCancellation: cancellation);
      if (!mounted ||
          request != _request ||
          ModalRoute.of(context)?.isCurrent == false) {
        result.cancelOnlineSearch();
        return;
      }
      _cancellation = null; // The results page now owns this request.
      context.push(app_paths.SEARCH_RESULT_PAGE, extra: result);
    } catch (error, trace) {
      if (!mounted || request != _request) return;
      LOGGER.w('[library search] $error', stackTrace: trace);
      setState(() => _error = ui('搜索暂时不可用，请重试。'));
    } finally {
      if (mounted && request == _request) {
        setState(() => _pendingQuery = null);
      }
    }
  }

  @override
  void dispose() {
    _request++;
    _cancellation?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: LayoutBuilder(builder: (context, page) {
        final bottom = math.min(
            page.maxHeight, NowPlayingBarMetrics.reservedSpace(context) + 16);
        final side = math.min(32.0, page.maxWidth * .075);
        return Padding(
          padding: EdgeInsets.fromLTRB(side, 16, side, bottom),
          child: LayoutBuilder(builder: (context, constraints) {
            final top = (constraints.maxHeight * .28 - 48).clamp(0.0, 120.0);
            final available = math.max(0.0, constraints.maxHeight - top);
            return Column(children: [
              SizedBox(height: top),
              // Only the form scrolls in exceptionally short/enlarged windows.
              // History always stays below it and above the player reservation.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: available),
                child: SingleChildScrollView(
                  child: AppEntrance(
                    identity: 'search-form',
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(ui('搜索'),
                          style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Hero(
                          tag: SEARCH_BAR_KEY,
                          child: Material(
                            type: MaterialType.transparency,
                            child: LibrarySearchField(
                              controller: _controller,
                              autofocus: true,
                              busy: _pendingQuery != null,
                              onChanged: _changed,
                              onSubmitted: _search,
                            ),
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!,
                              style: TextStyle(color: scheme.error)),
                        ),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: SearchHistoryLayout.normalWidth),
                      child: SearchHistoryCapsules(
                        history: _history,
                        onSearch: (query) {
                          _controller.text = query;
                          _changed(query);
                          unawaited(_search(query));
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ]);
          }),
        );
      }),
    );
  }
}
