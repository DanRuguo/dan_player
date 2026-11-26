import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/library_search_field.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_content_scrollbar.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/now_playing_bar_metrics.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/search/audio_search_query.dart';
import 'package:dan_player/search/search_history.dart';
import 'package:dan_player/page/search_page/search_history_capsules.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
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
  bool get localOnly => AudioSearchQuery.parse(query).hasStructuredSyntax;

  Future<OnlineSearchResponse> get online => _online;
  set online(Future<OnlineSearchResponse> value) {
    _online = value;
    _onlineInitialized = true;
    value.ignore();
  }

  UnionSearchResult(
    this.query, {
    OnlineSearchCancellation? onlineCancellation,
  }) : onlineCancellation = onlineCancellation ?? OnlineSearchCancellation();

  void cancelOnlineSearch() {
    onlineCancellation.cancel();
    if (_onlineInitialized) _online.ignore();
  }

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
    result.online = result.localOnly
        ? Future.value(const OnlineSearchResponse(tracks: [], failures: {}))
        : OnlineMusicService.instance.search(
            query,
            cancellation: result.onlineCancellation,
          );
    return result;
  }
}

// ignore: non_constant_identifier_names
final SEARCH_BAR_KEY = GlobalKey();

typedef LibrarySearch = Future<UnionSearchResult> Function(
  String query, {
  OnlineSearchCancellation? onlineCancellation,
});

const _quickSearchPresets = <(String, String, IconData)>[
  ('高音质无损', 'format:flac,wav,alac', Icons.high_quality_outlined),
  ('高分收藏', 'rating:4..5', Icons.star_outline_rounded),
  ('近30天入库', 'added:>=today-30d', Icons.schedule_rounded),
  ('常听热歌', 'playcount:>=10', Icons.local_fire_department_outlined),
  ('未听曲目', 'playcount:0', Icons.explore_outlined),
];

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
    try {
      AudioSearchQuery.parse(value);
    } on AudioSearchQueryException catch (error) {
      setState(() => _error = ui(error.message));
      return;
    }
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
      _cancellation = null;
      context.push(app_paths.SEARCH_RESULT_PAGE, extra: result);
    } catch (error, trace) {
      if (!mounted || request != _request) return;
      LOGGER.w('[library search] $error', stackTrace: trace);
      setState(() => _error = error is AudioSearchQueryException
          ? ui(error.message)
          : ui('搜索暂时不可用，请重试。'));
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: LayoutBuilder(builder: (context, page) {
        final bottom = math.min(
            page.maxHeight, NowPlayingBarMetrics.reservedSpace(context) + 16);
        final side = math.min(32.0, page.maxWidth * .075);
        final shortPage = page.maxHeight < 520;
        return Padding(
          padding: EdgeInsets.fromLTRB(side, 16, side, bottom),
          child: LayoutBuilder(builder: (context, constraints) {
            final top = (constraints.maxHeight * .22 - 44).clamp(0.0, 96.0);
            final available = math.max(0.0, constraints.maxHeight - top);
            return Column(children: [
              SizedBox(height: top),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: available),
                child: SingleChildScrollView(
                  child: AppEntrance(
                    identity: 'search-form',
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (!shortPage) ...[
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                scheme.primaryContainer,
                                scheme.secondaryContainer,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: .18),
                            ),
                          ),
                          child: Icon(
                            Icons.manage_search_rounded,
                            size: 28,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(ui('搜索'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3)),
                      if (!shortPage) ...[
                        const SizedBox(height: 6),
                        Text(
                          ui('支持歌名、艺术家、专辑、拼音首字母与本地高级语法筛选'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
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
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: AppShape.pillRadius,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!shortPage) ...[
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final preset in _quickSearchPresets)
                                _QuickFilterChip(
                                  key: ValueKey('search-preset-${preset.$2}'),
                                  label: ui(preset.$1),
                                  icon: preset.$3,
                                  tooltip: preset.$2,
                                  onTap: () {
                                    _controller.text = preset.$2;
                                    _changed(preset.$2);
                                    unawaited(_search(preset.$2));
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                      const LocalSearchHelpEntry(),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.zero,
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

class _QuickFilterChip extends StatefulWidget {
  const _QuickFilterChip({
    super.key,
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_QuickFilterChip> createState() => _QuickFilterChipState();
}

class _QuickFilterChipState extends State<_QuickFilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = AppMotion.duration(
      context,
      MotionKind.feedback,
      AppMotion.quick,
    );
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotion.standardCurve,
          decoration: BoxDecoration(
            color: _hovered
                ? scheme.secondaryContainer.withValues(alpha: 0.72)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _hovered
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 15, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared by the landing and results pages, using the app's dialog controls.
class LocalSearchHelpEntry extends StatelessWidget {
  const LocalSearchHelpEntry(
      {super.key, this.inResults = false, this.compact = false});
  final bool inResults;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    if (inResults) {
      return Tooltip(
        message: ui('本地筛选用法'),
        child: compact
            ? IconButton(
                key: const ValueKey('result-local-search-help'),
                tooltip: ui('本地筛选用法'),
                onPressed: () => showLocalSearchHelp(context),
                icon: const Icon(Symbols.help_outline),
              )
            : TextButton.icon(
                key: const ValueKey('result-local-search-help'),
                onPressed: () => showLocalSearchHelp(context),
                icon: const Icon(Symbols.help_outline, size: 18),
                label: Text(ui('本地筛选用法')),
              ),
      );
    }
    return Padding(
      key: ValueKey(inResults ? 'result-help-spacing' : 'landing-help-spacing'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          key: ValueKey(
              inResults ? 'result-local-search-help' : 'local-search-help'),
          onPressed: () => showLocalSearchHelp(context),
          icon: const Icon(Symbols.help_outline, size: 17),
          label: Text(ui('本地筛选用法')),
        ),
      ),
    );
  }
}

Future<void> showLocalSearchHelp(BuildContext context) => showAppDialog<void>(
      context: context,
      builder: (_) => const LocalSearchHelpDialog(),
    );

class LocalSearchHelpDialog extends StatelessWidget {
  const LocalSearchHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 480;
    final short = screen.height < 360;
    return Dialog(
      insetPadding:
          EdgeInsets.symmetric(horizontal: 16, vertical: short ? 12 : 24),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 24,
            vertical: short ? 12 : (compact ? 16 : 24)),
        child: AppDialogContent(
          width: 540,
          maxHeight:
              math.max(0, screen.height - (short ? 48 : (compact ? 80 : 96))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogTitle(ui('本地筛选用法'),
                  leading: const Icon(Symbols.help_outline),
                  style: short
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.titleLarge),
              SizedBox(height: short ? 8 : 16),
              Flexible(
                  child: AppContentScrollbar(
                builder: (_, controller) => SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.only(right: 10),
                  child: _examples(context),
                ),
              )),
              SizedBox(height: short ? 8 : 16),
              AppDialogActions(children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(ui('关闭')),
                )
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _examples(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ui('空格或 AND 表示同时满足，OR 或 | 表示任意满足；括号可组合条件，-(...) 可排除整组。')),
        const SizedBox(height: 8),
        Text(ui('带筛选语法的查询只读取本地乐库、个人记录与播放统计，不请求在线歌源。')),
        const SizedBox(height: 16),
        for (final row in const [
          ('标题、艺术家与专辑（支持拼音）', 'title:晴天 artist:zjl album:叶惠美'),
          ('目录或完整路径', 'folder:"C:/Music/Live" path:concert'),
          ('文件格式（逗号表示任选其一）', 'format:flac,mp3'),
          ('时长范围或比较（秒或分:秒）', 'duration:3:00..5:00  duration:>=180'),
          ('排除词或条件；引号内精确匹配', '-live -format:mp3 title:"love story"'),
          (
            '文件名、作曲家、专辑艺术家与原语言标签',
            'filename:live composer:莫扎特 albumartist:"Various Artists" language:ja'
          ),
          (
            '音质与音轨编号（数值支持 =、>、>=、<、<= 和范围）',
            'track:1..3 bitrate:>=320 samplerate:>=48kHz'
          ),
          ('文件大小（B、KB、MB、GB 或 KiB、MiB、GiB）', 'filesize:20MiB..100MiB'),
          ('个人评分与标签', 'rating:4..5 tag:"现场" | rating:unrated'),
          (
            '入库日与最后播放日（本机日历日）',
            'added:>=2026-01-01 lastplayed:2026-09-01..2026-09-26'
          ),
          (
            '相对日期：今天、昨天或 N 天前',
            'added:>=today-7d lastplayed:<today-30d\nlastplayed:yesterday | lastplayed:today'
          ),
          (
            '播放次数、完成次数、跳过次数与累计收听时长',
            'playcount:<5 completed:>=1 skipped:0 listened:>=30:00'
          ),
          ('存在或缺失元数据与个人记录', 'has:composer -has:language -has:tag'),
          (
            '组合示例：高音质或高评分，并排除现场版本',
            '(format:flac | rating:>=4) -filename:live'
          ),
        ]) ...[
          Text(ui(row.$1), style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: AppShape.smallRadius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: SelectableText(
              row.$2,
              style: TextStyle(
                color: scheme.primary,
                fontFamily: 'Consolas',
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        Text(ui('language 与 tag 按完整标签匹配；语言不根据文件名猜测。')),
        const SizedBox(height: 12),
        Text(ui('未知数值与尚未读完的元数据不会被排除条件误当成“不符合”；has 查询已读字段是否存在，旧统计归属不明时保持未知。')),
        const SizedBox(height: 12),
        Text(ui('入库日沿用个人乐库记录，旧曲目可能保留创建日期回填；文件大小是扫描快照，搜索不会重新读取音乐文件。')),
        const SizedBox(height: 12),
        Text(ui(
            'today-Nd 表示本机日历的 N 天前，支持 0–36500 天且不早于 1970 年。相对日期在每次搜索时计算，也可与固定日期组成范围。')),
        const SizedBox(height: 12),
        Text(ui('普通搜索支持拼音、首字母、西文重音与全角字母；拼写接近的结果排在直接匹配之后。')),
        const SizedBox(height: 12),
        Text(ui('4–64 位拉丁字母或数字词可容忍一次漏字、多字、错字或相邻字符颠倒；引号与筛选条件保持原有匹配规则。')),
      ],
    );
  }
}
