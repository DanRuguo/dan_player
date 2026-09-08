import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

Future<void> showSmartMatchDetails(BuildContext context, SmartPlaylist rule,
        List<Audio> library, Set<String> visible) =>
    showAppDialog<void>(
        context: context,
        builder: (_) =>
            _SmartMatchDialog(rule: rule, library: library, visible: visible));

class _SmartMatchDialog extends StatefulWidget {
  const _SmartMatchDialog(
      {required this.rule, required this.library, required this.visible});
  final SmartPlaylist rule;
  final List<Audio> library;
  final Set<String> visible;
  @override
  State<_SmartMatchDialog> createState() => _SmartMatchDialogState();
}

class _SmartMatchDialogState extends State<_SmartMatchDialog> {
  final _search = TextEditingController();
  Map<String, PersonalTrack>? _personal;
  late final _members = {
    for (final p in playlistTree.allPlaylists)
      p.id: p.flattenAudios().map((a) => a.stableTrackId).toSet()
  };
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await (await PersonalLibrary.instance).snapshot();
      if (mounted) setState(() => _personal = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Iterable<SmartCondition> _leaves(SmartCondition value) sync* {
    if (!value.isGroup) {
      yield value;
    } else {
      for (final child in value.children) {
        yield* _leaves(child);
      }
    }
  }

  String _explanation(Audio audio) {
    final rule = widget.rule;
    final data = _personal?[audio.stableTrackId];
    final parts = <String>[
      '${ui('歌名')}: ${audio.displayTitle}',
      '${ui('艺术家')}: ${audio.artist}',
      '${ui('专辑')}: ${audio.album}',
      '${ui('时长')}: ${audio.duration} s',
      if (rule.query.isNotEmpty) '${ui('关键词')}: ${rule.query}',
      if (rule.artist.isNotEmpty) '${ui('歌手包含')}: ${rule.artist}',
      if (rule.album.isNotEmpty) '${ui('专辑包含')}: ${rule.album}',
      if (rule.formats.isNotEmpty) '${ui('文件格式')}: ${rule.formats}',
      if (rule.minSeconds != null || rule.maxSeconds != null)
        '${ui('时长')}: ${rule.minSeconds ?? 0} – ${rule.maxSeconds ?? '∞'} s',
    ];
    const labels = ['评分至少', '个人标签包含', '首次入库不早于', '首次入库不晚于', '属于普通歌单'];
    if (rule.condition != null) {
      for (final term in _leaves(rule.condition!)) {
        final verdict = term.evaluate(audio.stableTrackId, data, _members);
        final value = term.field == SmartField.playlist
            ? playlistTree.findPlaylist(term.value)?.name ?? ui('暂不可用')
            : term.value;
        parts.add(
            '${term.exclude ? '${ui('排除')} · ' : ''}${ui(labels[term.field!.index])}: $value · ${ui(switch (verdict) {
          RuleTruth.yes => '满足',
          RuleTruth.no => '不满足',
          RuleTruth.unknown => '未知（不作为满足）'
        })}');
      }
    }
    parts.add(ui('结果同时受基础筛选、听歌记录、条件组和结果上限影响。'));
    return parts.join('\n');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = widget.library
        .where((a) => '${a.displayTitle} ${a.artist} ${a.album}'
            .toLowerCase()
            .contains(_search.text.toLowerCase()))
        .toList();
    return AlertDialog(
      title: AppDialogTitle(ui('匹配详情')),
      content: AppDialogContent(
          width: 640,
          maxHeight: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: ui('搜索歌曲'),
                    prefixIcon: const Icon(Icons.search))),
            const SizedBox(height: 12),
            if (_personal == null && _error == null)
              const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Flexible(
                child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final audio = tracks[index];
                      final matched = widget.visible.contains(audio.path);
                      return ExpansionTile(
                        title: Text(audio.displayTitle,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(ui(matched ? '已列入结果' : '未列入结果')),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        children: [
                          Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_explanation(audio)))
                        ],
                      );
                    })),
          ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(ui('关闭')))
      ],
    );
  }
}
