import 'package:dan_player/component/lyric_playback_preview.dart';
import 'package:dan_player/component/tap_lyric_editor.dart';
import 'package:dan_player/component/lyric_timing_dialog.dart';
import 'package:dan_player/component/lyric_format_picker.dart';
import 'package:dan_player/component/ffmpeg_setup_card.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:dan_player/lyric/cached_lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/page/now_playing_page/component/detail_progress_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path_util;
import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/ui_language.dart';

typedef OnlineLyricEditorSearch = Future<LyricSearchResponse> Function(
  Audio audio,
);
typedef OnlineLyricEditorCandidateLoader = Future<Lyric?> Function(
  SongSearchResult candidate,
);
typedef OnlineLyricEditorCustomCandidateLoader = Future<Lyric?> Function(
  Audio audio,
  CustomLyricSourceChoice choice,
);
typedef LocalLyricEditorLoader = Future<String> Function(Audio audio);

/// BASS exposes CUE playback positions relative to their segment. Match the
/// track identity before borrowing that clock: sibling CUE tracks can share
/// the same physical audio path.
double? matchingLyricEditorPlaybackPosition(
    Audio edited, Audio? playing, double position, double duration) {
  if (playing == null ||
      playing.stableTrackId != edited.stableTrackId ||
      !position.isFinite) {
    return null;
  }
  return position.clamp(0.0, duration);
}

typedef LyricEditorSourcePersistCallback = Future<void> Function(
  String audioPath,
  LyricSource source,
);

/// Replaces the sidecar and its source association as one recoverable unit.
/// The lyric-source helper owns index atomicity; this layer restores the LRC
/// when that second half fails so the file and association cannot diverge.
Future<void> persistEditedLyric({
  required String audioPath,
  required String sidecarPath,
  required String text,
  LyricEditorSourcePersistCallback? persistSource,
}) async {
  final target = File(sidecarPath);
  final temporary = File('$sidecarPath.tmp');
  final backup = File('$sidecarPath.bak');
  final hadPreviousSource = LYRIC_SOURCES.containsKey(audioPath);
  final previousSource = LYRIC_SOURCES[audioPath];
  final localSource = LyricSource(LyricSourceType.local);
  var movedTarget = false;
  var installedTarget = false;

  try {
    await temporary.writeAsString(text, encoding: utf8, flush: true);
    if (await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
      movedTarget = true;
    }
    await temporary.rename(target.path);
    installedTarget = true;
    await (persistSource ??
        (audioPath, source) => persistLyricSource(audioPath, source))(
      audioPath,
      localSource,
    );
  } catch (error, trace) {
    // persistLyricSource already restores its own mutation. The identity guard
    // also makes injected implementations recoverable without overwriting a
    // different source that may have been selected concurrently.
    if (identical(LYRIC_SOURCES[audioPath], localSource)) {
      if (hadPreviousSource) {
        LYRIC_SOURCES[audioPath] = previousSource!;
      } else {
        LYRIC_SOURCES.remove(audioPath);
      }
    }

    Object? rollbackFailure;
    StackTrace? rollbackTrace;
    if (installedTarget && await target.exists()) {
      try {
        await target.delete();
      } catch (rollbackError, rollbackStack) {
        rollbackFailure = rollbackError;
        rollbackTrace = rollbackStack;
      }
    }
    if (movedTarget && await backup.exists()) {
      try {
        if (await target.exists()) await target.delete();
        await backup.rename(target.path);
      } catch (rollbackError, rollbackStack) {
        rollbackFailure ??= rollbackError;
        rollbackTrace ??= rollbackStack;
      }
    }
    if (rollbackFailure != null) {
      LOGGER.e(
        '[lyric editor] rollback failed after $error: $rollbackFailure',
        stackTrace: rollbackTrace ?? trace,
      );
      throw StateError('无法恢复保存前的歌词文件：$rollbackFailure');
    }
    rethrow;
  } finally {
    if (await temporary.exists()) {
      try {
        await temporary.delete();
      } catch (_) {}
    }
  }
}

Future<bool> showLyricEditorDialog(
  BuildContext context,
  Audio audio, {
  OnlineLyricEditorSearch? onlineLyricSearch,
  OnlineLyricEditorCandidateLoader? onlineLyricCandidateLoader,
  List<CustomLyricSourceChoice>? customLyricChoices,
  OnlineLyricEditorCustomCandidateLoader? customLyricCandidateLoader,
}) async {
  if (audio.isOnline) {
    showAppNotice(ui("联网音乐的歌词为只读，不能修改"), kind: AppNoticeKind.warning);
    return false;
  }
  final quick = await chooseLyricEditingMethod(context);
  if (quick == null || !context.mounted) return false;
  if (quick) {
    return await showAppDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (tapContext) => TapLyricEditor(
                audio: audio,
                fetchOnline: () => showAppDialog<Lyric>(
                    context: tapContext,
                    builder: (_) => _OnlineLyricCandidateDialog(
                        audio: audio,
                        search:
                            onlineLyricSearch ?? searchManualLyricCandidates,
                        loadCandidate:
                            onlineLyricCandidateLoader ?? getLyricForCandidate,
                        customChoices: customLyricChoices ?? const [],
                        loadCustomCandidate: customLyricCandidateLoader ??
                            getLyricForCustomSourceChoice)),
                saveLyric: (lyric) async {
                  if (lyric is PlainLyric) {
                    final store = LyricDocumentStore.instance;
                    await store.load();
                    await store.saveDraft(audio, lyric,
                        expectedRevision: store.revisionFor(audio));
                    showAppNotice(ui('编辑副本已保存，手动选用后才用于播放'),
                        kind: AppNoticeKind.success);
                    return true;
                  }
                  final selected = await chooseLyricEditFormat(tapContext);
                  if (selected == null || !tapContext.mounted) return false;
                  return await showAppDialog<bool>(
                          context: tapContext,
                          barrierDismissible: false,
                          builder: (_) => LyricEditorDialog(
                              audio: audio,
                              initialFormat: selected,
                              initialLyric: lyric,
                              onlineLyricSearch: onlineLyricSearch,
                              onlineLyricCandidateLoader:
                                  onlineLyricCandidateLoader,
                              customLyricChoices: customLyricChoices,
                              customLyricCandidateLoader:
                                  customLyricCandidateLoader)) ==
                      true;
                })) ==
        true;
  }
  final format = await chooseLyricEditFormat(context);
  if (format == null || !context.mounted) return false;
  return await showAppDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => LyricEditorDialog(
          audio: audio,
          initialFormat: format,
          onlineLyricSearch: onlineLyricSearch,
          onlineLyricCandidateLoader: onlineLyricCandidateLoader,
          customLyricChoices: customLyricChoices,
          customLyricCandidateLoader: customLyricCandidateLoader,
        ),
      ) ==
      true;
}

class LyricEditorDialog extends StatefulWidget {
  const LyricEditorDialog({
    super.key,
    required this.audio,
    this.onlineLyricSearch,
    this.onlineLyricCandidateLoader,
    this.customLyricChoices,
    this.customLyricCandidateLoader,
    this.localLyricLoader,
    this.initialFormat = LyricEditFormat.lrc,
    this.initialLyric,
    this.preview,
    this.ensureTools,
  });

  final LyricEditFormat initialFormat;
  final Lyric? initialLyric;
  final LyricAudioPreview? preview;
  final Future<bool> Function()? ensureTools;
  final Audio audio;
  final OnlineLyricEditorSearch? onlineLyricSearch;
  final OnlineLyricEditorCandidateLoader? onlineLyricCandidateLoader;
  final List<CustomLyricSourceChoice>? customLyricChoices;
  final OnlineLyricEditorCustomCandidateLoader? customLyricCandidateLoader;
  final LocalLyricEditorLoader? localLyricLoader;

  @override
  State<LyricEditorDialog> createState() => _LyricEditorDialogState();
}

class _LyricEditorDialogState extends State<LyricEditorDialog> {
  final controller = TextEditingController();
  final translationController = TextEditingController();
  final romanizationController = TextEditingController();
  final focusNode = FocusNode();
  final _auditionFocus = FocusNode();
  late final FocusNode _auditionSliderFocus =
      FocusNode(onKeyEvent: _auditionKey);
  final _contentScroll = ScrollController();
  final _setupScroll = ScrollController();
  final _auditionTick = ValueNotifier<double>(0);
  final _auditionDrag = ValueNotifier<double?>(null);
  late final Listenable _auditionTimeline =
      Listenable.merge([_auditionTick, _auditionDrag]);
  late final LyricAudioPreview _audition =
      widget.preview ?? LyricAudioPreview(widget.audio);
  StreamSubscription<double>? _auditionClock;
  StreamSubscription<double>? _mainClock;
  double _auditionPosition = 0;
  bool _auditionTouched = false;
  bool _auditionChecking = false;
  bool _auditionReady = false;
  bool _auditionUnavailable = false;
  bool _auditionHandoff = false;
  int _auditionIntent = 0;
  int _dragIntent = 0;
  int? _dragPointer;
  double _dragOrigin = 0;
  bool _dragWasPlaying = false;
  Future<void>? _dragPause;
  String? _auditionError;
  late LyricEditFormat format;
  late LyricEditFormat _initialFormat;
  String _initialOriginal = '';
  String _initialTranslation = '';
  String _initialRomanization = '';
  String? _previewSource;
  bool? _previewAvailable;
  int _tab = 0;
  bool loading = true;
  bool saving = false;
  bool loadingOnline = false;
  String? loadError;
  String? onlineError;
  int _onlineLoadGeneration = 0;
  int _documentRevision = 0;
  bool get _busy => loading || saving || loadingOnline || _auditionHandoff;
  bool get _supportsPreview {
    if (format == LyricEditFormat.plain) return false;
    if (format != LyricEditFormat.lossless) return true;
    final source = controller.text;
    if (_previewSource == source && _previewAvailable != null) {
      return _previewAvailable!;
    }
    _previewSource = source;
    try {
      return _previewAvailable = _draft.parse() is! PlainLyric;
    } catch (_) {
      return _previewAvailable = false;
    }
  }

  bool get _hasAux =>
      format != LyricEditFormat.plain && format != LyricEditFormat.lossless;
  LyricEditDraft get _draft => LyricEditDraft(format, controller.text,
      translation: translationController.text,
      romanization: romanizationController.text);
  bool get dirty =>
      !loading &&
      (format != _initialFormat ||
          controller.text != _initialOriginal ||
          translationController.text != _initialTranslation ||
          romanizationController.text != _initialRomanization);
  void _rememberInitialDraft() {
    _initialFormat = format;
    _initialOriginal = controller.text;
    _initialTranslation = translationController.text;
    _initialRomanization = romanizationController.text;
  }

  TextEditingController get _activeController => _tab == 1
      ? translationController
      : _tab == 2
          ? romanizationController
          : controller;

  @override
  void initState() {
    super.initState();
    format = widget.initialFormat;
    if (PlayService.playbackReady.value) {
      final playback = PlayService.instance.playbackService;
      _auditionPosition = matchingLyricEditorPlaybackPosition(widget.audio,
              playback.nowPlaying, playback.position, _audition.duration) ??
          0;
      _auditionTick.value = _auditionPosition;
      _mainClock = playback.positionStream.listen((position) {
        if (!mounted || _auditionTouched) return;
        final current = matchingLyricEditorPlaybackPosition(widget.audio,
                playback.nowPlaying, position, _audition.duration) ??
            0;
        _auditionPosition = current;
        if (_tab != 3) _auditionTick.value = current;
      });
    }
    _audition.addListener(_auditionChanged);
    _auditionClock = _audition.positionStream.listen((position) {
      if (!mounted) return;
      _auditionPosition = position;
      if (!_auditionHandoff && _tab != 3) _auditionTick.value = position;
    });
    _rememberInitialDraft();
    _load();
  }

  void _auditionChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _prepareAudition() async {
    if (!mounted) return false;
    if (_auditionReady) return true;
    if (_auditionChecking) return false;
    setState(() {
      _auditionChecking = true;
      _auditionError = null;
    });
    try {
      final available =
          await (widget.ensureTools ?? () => FfmpegRuntime.shared.ensure())();
      if (!mounted) return false;
      if (!available) {
        setState(() => _auditionUnavailable = true);
        return false;
      }
      if (widget.preview == null) await _audition.prepare();
      if (!mounted) return false;
      final duration = _audition.duration;
      setState(() {
        _auditionUnavailable = false;
        _auditionReady = duration > 0;
        if (duration <= 0) _auditionError = ui('无法读取歌曲时长，无法试听。');
      });
      return _auditionReady;
    } catch (_) {
      if (mounted) {
        setState(() {
          _auditionUnavailable = true;
          _auditionError = ui('试听失败，请重试。');
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _auditionChecking = false);
    }
  }

  void _focusAudition() {
    focusNode.unfocus();
    _auditionFocus.requestFocus();
  }

  void _selectTab(int tab) {
    if (tab == _tab) return;
    focusNode.unfocus();
    if (tab == 3) {
      ++_auditionIntent;
      _cancelAuditionDrag(resume: false);
      unawaited(_audition.pause());
    }
    setState(() => _tab = tab);
    if (tab != 3) _auditionTick.value = _auditionPosition;
  }

  Future<void> _toggleAudition() async {
    if (_busy ||
        _auditionHandoff ||
        _auditionChecking ||
        _auditionDrag.value != null) {
      return;
    }
    final intent = ++_auditionIntent;
    _focusAudition();
    if (_audition.playing || _audition.loading) {
      await _audition.pause();
      return;
    }
    if (!await _prepareAudition() ||
        !mounted ||
        intent != _auditionIntent ||
        _busy) {
      return;
    }
    final end = _audition.duration;
    final start = _auditionPosition >= end ? 0.0 : _auditionPosition;
    _auditionTouched = true;
    await _audition.play(start, end);
  }

  Future<void> _seekAudition(double delta) async {
    if (_busy ||
        _auditionHandoff ||
        _auditionChecking ||
        _auditionDrag.value != null) {
      return;
    }
    _focusAudition();
    final end = _audition.duration;
    if (end <= 0) return;
    final target = (_auditionPosition + delta).clamp(0.0, end);
    _auditionTouched = true;
    _auditionPosition = target;
    _auditionTick.value = target;
    if ((_audition.playing || _audition.loading) && target < end) {
      await _audition.play(target, end);
    } else {
      await _audition.seekPaused(target);
    }
  }

  void _startAuditionDrag(double value) {
    if (_busy || _auditionChecking || _tab == 3) return;
    _focusAudition();
    _auditionTouched = true;
    _dragIntent = ++_auditionIntent;
    _dragOrigin = _auditionPosition;
    _dragWasPlaying = _audition.playing || _audition.loading;
    _dragPause = _audition.pause();
    _auditionDrag.value = value;
  }

  Future<void> _endAuditionDrag(double value) async {
    if (_auditionDrag.value == null) return;
    final intent = _dragIntent;
    final resume = _dragWasPlaying;
    final end = _audition.duration;
    final target = value.clamp(0.0, end);
    _dragPointer = null;
    _auditionPosition = target;
    _auditionTick.value = target;
    _auditionDrag.value = null;
    await _dragPause;
    if (!mounted || intent != _auditionIntent || _tab == 3) return;
    if (resume) {
      await _audition.play(target >= end ? 0.0 : target, end);
    } else {
      await _audition.seekPaused(target);
    }
  }

  void _cancelAuditionDrag({bool resume = true}) {
    if (_auditionDrag.value == null) return;
    final intent = _dragIntent;
    final wasPlaying = _dragWasPlaying;
    final origin = _dragOrigin;
    _dragPointer = null;
    _auditionDrag.value = null;
    _auditionPosition = origin;
    _auditionTick.value = origin;
    if (!resume) return;
    unawaited(() async {
      await _dragPause;
      if (!mounted || intent != _auditionIntent || _tab == 3) return;
      if (wasPlaying) {
        await _audition.play(origin, _audition.duration);
      } else {
        await _audition.seekPaused(origin);
      }
    }());
  }

  Future<void> _openAuditionSetup() async {
    await showAppDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              content: SizedBox(
                  width: 520,
                  child: AppScrollbar(
                      controller: _setupScroll,
                      child: SingleChildScrollView(
                          controller: _setupScroll,
                          child: FfmpegSetupCard(
                              lyricPreview: true,
                              onReady: () {
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                                unawaited(_prepareAudition());
                              })))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(ui('关闭')))
              ],
            ));
  }

  Future<void> _openPlaybackPreview(Lyric lyric, {int? line}) async {
    if (_busy ||
        _auditionChecking ||
        _auditionHandoff ||
        _auditionDrag.value != null) {
      return;
    }
    ++_auditionIntent;
    setState(() => _auditionHandoff = true);
    _auditionTouched = true;
    try {
      await _audition.pause();
      if (!mounted) return;
      await showLyricPlaybackPreview(context, widget.audio, lyric,
          line: line, preview: _audition, ensureTools: widget.ensureTools);
    } catch (_) {
      if (mounted) setState(() => _auditionError = ui('试听失败，请重试。'));
    } finally {
      await _audition.pause();
      if (mounted) {
        _auditionPosition = _audition.position;
        _auditionTick.value = _auditionPosition;
        setState(() => _auditionHandoff = false);
        _auditionFocus.requestFocus();
      }
    }
  }

  void _setDraft(LyricEditDraft draft) {
    format = draft.format;
    controller.text = draft.original;
    translationController.text = draft.translation;
    romanizationController.text = draft.romanization;
    if ((!_hasAux && (_tab == 1 || _tab == 2)) ||
        (!_supportsPreview && _tab == 3)) {
      _tab = 0;
    }
  }

  Future<void> _load() async {
    try {
      Lyric? lyric;
      if (widget.initialLyric != null) {
        await LyricDocumentStore.instance.load();
        _documentRevision =
            LyricDocumentStore.instance.revisionFor(widget.audio);
        lyric = widget.initialLyric;
      } else if (widget.localLyricLoader != null) {
        final text = await widget.localLyricLoader!(widget.audio);
        lyric = Lrc.fromLrcText(text, LrcSource.local, separator: '┃');
      } else {
        final store = LyricDocumentStore.instance;
        await store.load();
        final document = store.forAudio(widget.audio);
        _documentRevision = document?.revision ?? 0;
        lyric = document?.draft?.toLyric() ?? document?.effective?.toLyric();
        if (lyric == null && document?.noLyrics != true) {
          if (!widget.audio.isCueTrack) {
            for (final extension in [
              'lrc',
              'elrc',
              'qrc',
              'krc',
              'yrc',
              'danlyrics.json',
              'txt'
            ]) {
              final file = File(
                  path_util.setExtension(widget.audio.path, '.$extension'));
              if (await file.exists()) {
                lyric = (await readLyricEditFile(file)).parse();
                break;
              }
            }
          }
          lyric ??= await readAvailableCachedLyric(widget.audio,
              source: LYRIC_SOURCES[widget.audio.path]);
          if (lyric == null && !widget.audio.isCueTrack) {
            lyric = await Lrc.fromAudioPath(widget.audio, separator: '┃');
          }
        }
      }
      if (!mounted) return;
      if (lyric != null) {
        final selected = await _confirmConversion(lyric, format);
        if (!mounted) return;
        _setDraft(LyricEditDraft.fromLyric(
            lyric, selected ?? preferredLyricEditingFormat(lyric)));
      }
      _rememberInitialDraft();
    } catch (error, trace) {
      LOGGER.e('[lyric editor] load failed: $error', stackTrace: trace);
      loadError = ui('读取歌词失败：{0}', [_errorText(error)]);
      _rememberInitialDraft();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _errorText(Object error) => error is FormatException
      ? ui(error.message) + (error.source is int ? ' (${error.source})' : '')
      : error.toString();

  Future<LyricEditFormat?> _confirmConversion(Lyric lyric, LyricEditFormat next,
      {LyricEditFormat? keepFormat}) async {
    while (mounted) {
      if (lyricConversionPreservesData(lyric, next)) return next;
      final choice = await showAppDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                title: AppDialogTitle(ui('转换歌词格式？')),
                content: Text(ui('转换可能丢失逐字时间或辅助内容；纯文本转时间轴需要手动校时。原始版本仍保留。')),
                actions: [
                  TextButton.icon(
                      key: const ValueKey('lyric-conversion-back'),
                      onPressed: () => Navigator.pop(context, 'back'),
                      icon: const Icon(Symbols.arrow_back),
                      label: Text(ui('返回选择格式'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, 'keep'),
                      child: Text(ui('保留完整内容'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, 'convert'),
                      child: Text(ui('转换')))
                ],
              ));
      if (!mounted) return null;
      if (choice == 'convert') return next;
      if (choice != 'back') {
        return choice == 'keep'
            ? keepFormat ?? preferredLyricEditingFormat(lyric)
            : null;
      }
      final picked = await chooseLyricEditFormat(context, current: next);
      if (!mounted || picked == null) return null;
      next = picked;
    }
    return null;
  }

  Future<void> _changeFormat() async {
    final next = await chooseLyricEditFormat(context, current: format);
    if (next == null || next == format || !mounted) return;
    try {
      if (controller.text.trim().isEmpty &&
          translationController.text.isEmpty &&
          romanizationController.text.isEmpty) {
        setState(() => _setDraft(LyricEditDraft(next, '')));
        return;
      }
      final lyric = _draft.parse();
      final selected =
          await _confirmConversion(lyric, next, keepFormat: format);
      if (!mounted || selected == null || selected == format) return;
      setState(() => _setDraft(LyricEditDraft.fromLyric(lyric, selected)));
    } catch (error) {
      setState(() => onlineError = _errorText(error));
    }
  }

  Future<void> _loadExample() async {
    if (dirty && !await _confirmReplace()) return;
    if (!mounted) return;
    setState(() {
      _setDraft(lyricEditingExample(format));
      _tab = 0;
      loadError = null;
      onlineError = null;
    });
  }

  Future<void> _importFile() async {
    final picker = OpenFilePicker()
      ..title = ui('导入歌词')
      ..filterSpecification = {
        ui('歌词文件'): '*.lrc;*.elrc;*.qrc;*.krc;*.yrc;*.txt;*.json'
      };
    final file = picker.getFile();
    if (file == null) return;
    setState(() => saving = true);
    try {
      final imported = await readLyricEditFile(file);
      final parsed = imported.parse();
      if (!mounted) return;
      if (dirty && !await _confirmReplace()) return;
      if (!mounted) return;
      setState(() {
        _setDraft(LyricEditDraft.fromLyric(parsed, imported.format));
        loadError = null;
        onlineError = null;
      });
    } catch (error) {
      if (mounted) setState(() => onlineError = _errorText(error));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<bool> _confirmReplace() async =>
      await showAppDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: AppDialogTitle(ui('替换编辑中的内容？')),
                  content: Text(ui('尚未保存的内容将丢失。')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(ui('取消'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(ui('替换')))
                  ])) ==
      true;

  Future<void> _fillOnlineLyric() async {
    if (loading || saving || loadingOnline) return;
    final generation = ++_onlineLoadGeneration;
    setState(() {
      loadingOnline = true;
      onlineError = null;
    });

    final lyric = await showAppDialog<Lyric>(
      context: context,
      builder: (_) => _OnlineLyricCandidateDialog(
        audio: widget.audio,
        search: widget.onlineLyricSearch ?? searchManualLyricCandidates,
        loadCandidate:
            widget.onlineLyricCandidateLoader ?? getLyricForCandidate,
        customChoices: widget.customLyricChoices ?? const [],
        loadCustomCandidate:
            widget.customLyricCandidateLoader ?? getLyricForCustomSourceChoice,
      ),
    );

    if (!mounted || generation != _onlineLoadGeneration) return;
    if (lyric == null) {
      setState(() => loadingOnline = false);
      return;
    }
    setState(() => loadingOnline = false);
    if (!hasLyricContent(lyric)) {
      setState(() => onlineError = ui('该候选没有返回可用歌词，可选择其他候选或重试。'));
      return;
    }
    if (dirty && !await _confirmReplace()) return;
    if (!mounted) return;
    final convert = await _confirmConversion(lyric, format);
    if (!mounted || convert == null) return;
    setState(() {
      _setDraft(LyricEditDraft.fromLyric(lyric, convert));
      loadError = null;
      onlineError = null;
    });
  }

  int _currentMilliseconds() {
    if (!_auditionTouched && PlayService.playbackReady.value) {
      final playback = PlayService.instance.playbackService;
      final current = matchingLyricEditorPlaybackPosition(widget.audio,
          playback.nowPlaying, playback.position, _audition.duration);
      if (current != null) return (current * 1000).round();
      return 0;
    }
    return (_auditionPosition * 1000).round();
  }

  Future<void> _insertCurrentTimestamp() async {
    final target = _activeController;
    final offset =
        target.selection.isValid ? target.selection.start : target.text.length;
    final rowStart =
        offset == 0 ? 0 : target.text.lastIndexOf('\n', offset - 1) + 1;
    final next = target.text.indexOf('\n', offset);
    final rowEnd = next < 0 ? target.text.length : next;
    final row = target.text.substring(rowStart, rowEnd);
    final mode = _tab == 0 ? format : LyricEditFormat.lrc;
    final ms = _currentMilliseconds();
    var end = ms + 1000;
    final oldStart = mode == LyricEditFormat.lrc ||
            mode == LyricEditFormat.enhanced
        ? LrcLine.fromLine(row)?.start.inMilliseconds
        : int.tryParse(RegExp(r'^\[(\d+),').firstMatch(row)?.group(1) ?? '');
    void applyRow(int start, int endTime) {
      final replacement = retimeLyricEditorRow(row, mode, start, endTime);
      if (_tab == 0 && oldStart != null) {
        final translated = retimeLyricAuxiliaryRows(
            translationController.text, oldStart, start);
        final romanized = retimeLyricAuxiliaryRows(
            romanizationController.text, oldStart, start);
        translationController.text = translated;
        romanizationController.text = romanized;
      }
      _replaceRange(target, rowStart, rowEnd, replacement);
    }

    try {
      if (mode.timedWords) {
        try {
          final parsed = LyricEditDraft(mode, row).parse();
          final line = parsed.lines
              .whereType<SyncLyricLine>()
              .firstWhere((l) => l.words.isNotEmpty);
          end = ms + line.length.inMilliseconds;
        } catch (_) {/* An untimed draft line receives its first time range. */}
        final times =
            await showLyricTimingDialog(context, startMs: ms, endMs: end);
        if (times == null || !mounted) return;
        applyRow(times.$1, times.$2);
      } else {
        applyRow(ms, ms);
      }
    } catch (error) {
      if (mounted) setState(() => onlineError = _errorText(error));
    }
  }

  Future<void> _timeSelectedWord() async {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      setState(() => onlineError = ui('请选择不含时间标记的文字'));
      return;
    }
    final rowStart = selection.start == 0
        ? 0
        : controller.text.lastIndexOf('\n', selection.start - 1) + 1;
    final next = controller.text.indexOf('\n', rowStart);
    final row = controller.text
        .substring(rowStart, next < 0 ? controller.text.length : next);
    final header = format == LyricEditFormat.enhanced
        ? RegExp(r'^\[(\d+):(\d+)(?:\.(\d+))?\]')
        : RegExp(r'^\[(\d+),(\d+)\]');
    final match = header.firstMatch(row);
    if (match == null ||
        selection.start < rowStart + match.end ||
        (next >= 0 && selection.end > next)) {
      setState(() => onlineError = ui('请先设置当前行时间，再选择该行的文字'));
      return;
    }
    final lineStart = format == LyricEditFormat.enhanced
        ? LrcLine.fromLine(row)!.start.inMilliseconds
        : int.parse(match[1]!);
    final lineEnd = format == LyricEditFormat.enhanced
        ? 86400000
        : lineStart + int.parse(match[2]!);
    final current = _currentMilliseconds().clamp(lineStart, lineEnd);
    final times = await showLyricTimingDialog(context,
        startMs: current, endMs: (current + 500).clamp(current, lineEnd));
    if (times == null || !mounted) return;
    try {
      if (times.$2 > lineEnd) throw const FormatException('逐字时间超出所在行范围');
      final replacement = replaceTimedLyricWord(
          row,
          format,
          selection.start - rowStart,
          selection.end - rowStart,
          times.$1,
          times.$2,
          lineStartMs: lineStart);
      _replaceRange(controller, rowStart, rowStart + row.length, replacement);
    } catch (error) {
      setState(() => onlineError = _errorText(error));
    }
  }

  void _replaceRange(
      TextEditingController target, int start, int end, String value) {
    target.value = TextEditingValue(
        text: target.text.replaceRange(start, end, value),
        selection: TextSelection.collapsed(offset: start + value.length));
    focusNode.requestFocus();
    setState(() => onlineError = null);
  }

  Future<void> _save() async {
    Lyric parsed;
    try {
      parsed = _draft.parse();
    } catch (error) {
      setState(() => onlineError = _errorText(error));
      return;
    }
    ++_auditionIntent;
    _cancelAuditionDrag(resume: false);
    await _audition.pause();
    if (!mounted) return;
    setState(() => saving = true);
    try {
      await LyricDocumentStore.instance
          .saveDraft(widget.audio, parsed, expectedRevision: _documentRevision);
    } catch (error, trace) {
      LOGGER.e("[lyric editor] save failed: $error", stackTrace: trace);
      showAppNotice(ui("保存歌词失败：{0}", [_errorText(error)]),
          kind: AppNoticeKind.error);
      if (mounted) setState(() => saving = false);
      return;
    }

    _rememberInitialDraft();
    showAppNotice(ui('编辑副本已保存，手动选用后才用于播放'), kind: AppNoticeKind.success);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _cancel() async {
    ++_auditionIntent;
    _cancelAuditionDrag(resume: false);
    await _audition.pause();
    if (!mounted) return;
    if (!dirty) {
      Navigator.pop(context, false);
      return;
    }
    final discard = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppDialogTitle(ui("放弃歌词修改？")),
        content: Text(ui("尚未保存的内容将丢失。")),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ui("继续编辑")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ui("放弃修改")),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context, false);
  }

  Future<void> _exportSidecar() async {
    try {
      _draft.parse();
      final picker = SaveFilePicker()
        ..title = ui('导出歌词')
        ..fileName =
            '${path_util.basenameWithoutExtension(widget.audio.path)}.edited.${format.extension}'
        ..defaultExtension = format.extension
        ..filterSpecification = {ui(format.label): '*.${format.extension}'};
      final file = picker.getFile();
      if (file == null || !mounted) return;
      if (path_util.windows.equals(file.path, widget.audio.path) ||
          !file.path.toLowerCase().endsWith('.${format.extension}')) {
        throw const FormatException('请选择对应格式的歌词文件');
      }
      final files = _draft.exportFiles(file.path);
      final confirmed = await showAppDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: AppDialogTitle(ui('导出歌词')),
                  content: SingleChildScrollView(
                      child: Text(ui('以下文件将写入，已有内容保留备份；翻译和注音使用独立 LRC 文件。\n{0}',
                          [files.keys.join('\n')]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(ui('取消'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(ui('确认导出')))
                  ]));
      if (confirmed != true || !mounted) return;
      setState(() => saving = true);
      await writeLyricExport(files);
      showAppNotice(ui('歌词已保存到 {0}', [file.path]), kind: AppNoticeKind.success);
    } catch (error) {
      if (mounted) setState(() => onlineError = _errorText(error));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    _onlineLoadGeneration++;
    _audition.removeListener(_auditionChanged);
    unawaited(_auditionClock?.cancel());
    unawaited(_mainClock?.cancel());
    _audition.dispose();
    _auditionTick.dispose();
    _auditionDrag.dispose();
    controller.dispose();
    translationController.dispose();
    romanizationController.dispose();
    focusNode.dispose();
    _auditionFocus.dispose();
    _auditionSliderFocus.dispose();
    _contentScroll.dispose();
    _setupScroll.dispose();
    super.dispose();
  }

  // Auxiliary tracks use LRC timestamps even when the original uses QRC/KRC/YRC.
  String _auditionStamp(double seconds) {
    final milliseconds = (seconds * 1000).round();
    if (_tab == 0 &&
        (format == LyricEditFormat.qrc ||
            format == LyricEditFormat.krc ||
            format == LyricEditFormat.yrc)) {
      return '$milliseconds ${ui('毫秒')}';
    }
    return lyricStamp(Duration(milliseconds: milliseconds));
  }

  Widget _auditionControls(ColorScheme scheme) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600 || size.height < 500;
    final short = size.height < 500;
    final dense = short && MediaQuery.textScalerOf(context).scale(14) > 21;
    return Container(
      padding: EdgeInsets.all(short ? 8 : 12),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: AppShape.controlRadius,
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: .6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (dense)
                IconButton.filled(
                    key: const ValueKey('lyric-editor-audition-play'),
                    tooltip: ui(_audition.playing ? '暂停' : '播放'),
                    style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: AppShape.control),
                    onPressed:
                        _busy || _auditionChecking ? null : _toggleAudition,
                    icon: Icon(
                        _audition.playing ? Symbols.pause : Symbols.play_arrow))
              else
                FilledButton.icon(
                    key: const ValueKey('lyric-editor-audition-play'),
                    onPressed:
                        _busy || _auditionChecking ? null : _toggleAudition,
                    icon: Icon(
                        _audition.playing ? Symbols.pause : Symbols.play_arrow),
                    label: Text(ui(_audition.playing ? '暂停' : '播放'))),
              if (short) ...[
                Tooltip(
                    message: ui('后退 100 毫秒'),
                    child: IconButton.outlined(
                        key: const ValueKey('lyric-editor-audition-back'),
                        style: dense
                            ? IconButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                shape: AppShape.control)
                            : null,
                        onPressed: _busy ||
                                _auditionChecking ||
                                _audition.duration <= 0
                            ? null
                            : () => _seekAudition(-.1),
                        icon: const Icon(Symbols.keyboard_arrow_left))),
                if (!dense)
                  Text('100 ms',
                      style: Theme.of(context).textTheme.labelMedium),
                Tooltip(
                    message: ui('前进 100 毫秒'),
                    child: IconButton.outlined(
                        key: const ValueKey('lyric-editor-audition-forward'),
                        style: dense
                            ? IconButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                shape: AppShape.control)
                            : null,
                        onPressed: _busy ||
                                _auditionChecking ||
                                _audition.duration <= 0
                            ? null
                            : () => _seekAudition(.1),
                        icon: const Icon(Symbols.keyboard_arrow_right))),
              ] else ...[
                Tooltip(
                  message: ui('后退 100 毫秒'),
                  child: OutlinedButton.icon(
                      key: const ValueKey('lyric-editor-audition-back'),
                      onPressed:
                          _busy || _auditionChecking || _audition.duration <= 0
                              ? null
                              : () => _seekAudition(-.1),
                      icon: const Icon(Symbols.keyboard_arrow_left),
                      label: Text(compact ? '−100 ms' : ui('后退 100 毫秒'))),
                ),
                Tooltip(
                  message: ui('前进 100 毫秒'),
                  child: OutlinedButton.icon(
                      key: const ValueKey('lyric-editor-audition-forward'),
                      onPressed:
                          _busy || _auditionChecking || _audition.duration <= 0
                              ? null
                              : () => _seekAudition(.1),
                      icon: const Icon(Symbols.keyboard_arrow_right),
                      label: Text(compact ? '+100 ms' : ui('前进 100 毫秒'))),
                ),
              ],
              if (dense)
                AnimatedBuilder(
                    animation: _auditionTimeline,
                    builder: (context, _) => Tooltip(
                        message:
                            '${ui('当前时刻')} ${_auditionStamp(_auditionDrag.value ?? _auditionTick.value)} / ${_auditionStamp(_audition.duration)}',
                        child: Text(
                            _auditionStamp(
                                _auditionDrag.value ?? _auditionTick.value),
                            key:
                                const ValueKey('lyric-editor-audition-time')))),
            ]),
        RepaintBoundary(
            child: AnimatedBuilder(
                animation: _auditionTimeline,
                builder: (context, _) {
                  final end = _audition.duration;
                  final position = _auditionDrag.value ?? _auditionTick.value;
                  final timeCaption = short ? '' : '${ui('当前时刻')} ';
                  final enabled = !_busy && !_auditionChecking && end > 0;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (end > 0 && !_auditionUnavailable)
                          Listener(
                              onPointerDown: (event) =>
                                  _dragPointer ??= event.pointer,
                              onPointerUp: (event) {
                                if (_dragPointer == event.pointer) {
                                  _dragPointer = null;
                                }
                              },
                              onPointerCancel: (event) {
                                if (_dragPointer == event.pointer) {
                                  _cancelAuditionDrag();
                                }
                              },
                              child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                      trackHeight: 4,
                                      trackShape:
                                          const RoundedRectSliderTrackShape(),
                                      thumbShape:
                                          const DetailProgressHandleShape(
                                              emphasis: 0),
                                      overlayShape:
                                          SliderComponentShape.noOverlay,
                                      activeTrackColor: scheme.primary,
                                      inactiveTrackColor:
                                          scheme.primary.withValues(alpha: .18),
                                      thumbColor: scheme.primary,
                                      valueIndicatorColor:
                                          scheme.primaryContainer,
                                      valueIndicatorTextStyle: TextStyle(
                                          color: scheme.onPrimaryContainer),
                                      showValueIndicator:
                                          ShowValueIndicator.onDrag),
                                  child: Semantics(
                                      label: ui('播放进度'),
                                      child: Slider(
                                          key: const ValueKey(
                                              'lyric-editor-audition-seek'),
                                          focusNode: _auditionSliderFocus,
                                          min: 0,
                                          max: end > 0 ? end : 1,
                                          value: position.clamp(
                                              0.0, end > 0 ? end : 1),
                                          label: _auditionStamp(position),
                                          semanticFormatterCallback:
                                              _auditionStamp,
                                          onChangeStart: enabled
                                              ? _startAuditionDrag
                                              : null,
                                          onChanged: enabled
                                              ? (value) {
                                                  if (_auditionDrag.value !=
                                                      null) {
                                                    _auditionDrag.value = value;
                                                  }
                                                }
                                              : null,
                                          onChangeEnd: enabled
                                              ? (value) => unawaited(
                                                  _endAuditionDrag(value))
                                              : null)))),
                        if (!dense)
                          Row(children: [
                            Flexible(
                                child: Tooltip(
                                    message: ui('当前时刻'),
                                    child: Text(
                                        '$timeCaption${_auditionStamp(position)} / ${_auditionStamp(end)}',
                                        key: const ValueKey(
                                            'lyric-editor-audition-time'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis))),
                            if (compact) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                  message: ui('空格播放或暂停；左右方向键每次移动 100 毫秒。'),
                                  child: Icon(Icons.keyboard_outlined,
                                      size: 16,
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ]),
                      ]);
                })),
        if (!compact) ...[
          const SizedBox(height: 6),
          Text(ui('空格播放或暂停；左右方向键每次移动 100 毫秒。'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        if (_auditionChecking || _audition.loading)
          const LinearProgressIndicator(),
        if (_auditionUnavailable)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                      key: const ValueKey('lyric-editor-audition-install'),
                      onPressed: _openAuditionSetup,
                      icon: const Icon(Icons.build_outlined),
                      label: Text(ui('安装试听组件'))))),
        if (_auditionError != null || _audition.error != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_auditionError ?? ui(_audition.error!),
                  style: TextStyle(color: scheme.error))),
      ]),
    );
  }

  Widget _preview(ColorScheme scheme) {
    try {
      final lyric = _draft.parse();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
                key: const ValueKey('lyric-editor-play-preview'),
                onPressed: _busy || _auditionChecking
                    ? null
                    : () => _openPlaybackPreview(lyric),
                icon: const Icon(Symbols.play_arrow),
                label: Text(ui('播放编辑预览')))),
        const SizedBox(height: 12),
        Text(ui('预览最多显示 100 行，每行展示前 80 个时间片段；保存包含全部内容。'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final (index, line) in lyric.lines.indexed
            .where((entry) => lyricLineText(entry.$2).trim().isNotEmpty)
            .take(100))
          Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppShape.controlRadius),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (lyric is! PlainLyric)
                      Row(children: [
                        Expanded(
                            child: Text(lyricStamp(line.start),
                                style: TextStyle(
                                    color: scheme.primary, fontSize: 12))),
                        IconButton.outlined(
                            key: ValueKey('lyric-line-preview-$index'),
                            tooltip: ui('逐句试听'),
                            onPressed: _busy || _auditionChecking
                                ? null
                                : () =>
                                    _openPlaybackPreview(lyric, line: index),
                            icon: const Icon(Symbols.play_arrow)),
                      ]),
                    if (line.romanization?.isNotEmpty == true)
                      Text(line.romanization!,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    Text(lyricLineText(line).split('┃').first,
                        style: Theme.of(context).textTheme.titleMedium),
                    if (line is SyncLyricLine &&
                        line.translation?.isNotEmpty == true)
                      Text(line.translation!),
                    if (line is UnsyncLyricLine && line.content.contains('┃'))
                      Text(line.content.split('┃').skip(1).join('┃')),
                    if (line is SyncLyricLine)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final word in line.words.take(80))
                              Chip(
                                  label: Text(
                                      '${word.content} · ${word.length.inMilliseconds} ms'),
                                  visualDensity: VisualDensity.compact),
                          ])),
                  ])),
      ]);
    } catch (error) {
      return Text(_errorText(error), style: TextStyle(color: scheme.error));
    }
  }

  Widget _toolbar(ThemeData theme, ColorScheme scheme) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    Widget action(String label, IconData icon, VoidCallback callback,
            {String? key}) =>
        compact && key != 'lyric-editor-format'
            ? IconButton.outlined(
                key: key == null ? null : ValueKey(key),
                tooltip: ui(label),
                style: IconButton.styleFrom(shape: AppShape.control),
                onPressed: _busy ? null : callback,
                icon: Icon(icon))
            : OutlinedButton.icon(
                key: key == null ? null : ValueKey(key),
                style: OutlinedButton.styleFrom(shape: AppShape.control),
                onPressed: _busy ? null : callback,
                icon: Icon(icon),
                label: Text(ui(label)));
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppShape.controlRadius,
            border:
                Border.all(color: scheme.outlineVariant.withValues(alpha: .6))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                action(format.label, Symbols.tune, _changeFormat,
                    key: 'lyric-editor-format'),
                action('导出歌词', Symbols.save_alt, _exportSidecar,
                    key: 'lyric-editor-export'),
                if (compact)
                  IconButton.outlined(
                      key: const ValueKey('lyric-editor-compact-guide'),
                      tooltip:
                          '${ui(_supportsPreview ? '选择格式 → 编辑内容 → 试听检查 → 保存副本' : '选择格式 → 编辑内容 → 保存副本')}\n${ui('保存为编辑副本；只有手动选用后才替换播放歌词。')}',
                      style: IconButton.styleFrom(shape: AppShape.control),
                      onPressed: () => showAppNotice(
                          '${ui(_supportsPreview ? '选择格式 → 编辑内容 → 试听检查 → 保存副本' : '选择格式 → 编辑内容 → 保存副本')}\n${ui('保存为编辑副本；只有手动选用后才替换播放歌词。')}'),
                      icon: const Icon(Symbols.info)),
              ]),
          if (!compact) ...[
            const SizedBox(height: 10),
            Text(ui(_supportsPreview
                ? '选择格式 → 编辑内容 → 试听检查 → 保存副本'
                : '选择格式 → 编辑内容 → 保存副本')),
            const SizedBox(height: 6),
            Text(ui('保存为编辑副本；只有手动选用后才替换播放歌词。'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            action('载入示例', Symbols.science, _loadExample,
                key: 'lyric-editor-example'),
            action('导入歌词', Symbols.file_open, _importFile),
            action('填入联网歌词', Symbols.cloud_download, _fillOnlineLyric,
                key: 'lyric-editor-fill-online'),
            if (compact && _hasAux && _tab != 3) ...[
              const SizedBox(width: 8),
              action('设置当前行时间', Symbols.timer, _insertCurrentTimestamp,
                  key: 'lyric-editor-insert-time'),
              if (format.timedWords && _tab == 0)
                action('设置所选文字时间', Symbols.av_timer, _timeSelectedWord,
                    key: 'lyric-editor-word-time'),
            ],
          ]),
          if (!compact && _hasAux && _tab != 3) ...[
            const Divider(height: 24),
            Wrap(spacing: 8, runSpacing: 8, children: [
              action('设置当前行时间', Symbols.timer, _insertCurrentTimestamp,
                  key: 'lyric-editor-insert-time'),
              if (format.timedWords && _tab == 0)
                action('设置所选文字时间', Symbols.av_timer, _timeSelectedWord,
                    key: 'lyric-editor-word-time'),
            ]),
          ],
        ]));
  }

  KeyEventResult _auditionKey(FocusNode node, KeyEvent event) {
    if (_busy ||
        _auditionChecking ||
        _tab == 3 ||
        focusNode.hasFocus ||
        ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.space) {
        unawaited(_toggleAudition());
      } else {
        unawaited(
            _seekAudition(key == LogicalKeyboardKey.arrowLeft ? -.1 : .1));
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context), scheme = Theme.of(context).colorScheme;
    final aux = _tab == 1 || _tab == 2;
    return PopScope<bool>(
      canPop: !dirty && !saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !saving) _cancel();
      },
      child: Focus(
        focusNode: _auditionFocus,
        autofocus: true,
        onKeyEvent: _auditionKey,
        child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: AppDialogContent(
              width: 900,
              maxHeight: (MediaQuery.sizeOf(context).height - 48)
                  .clamp(200, 800)
                  .toDouble(),
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppDialogTitle(
                            ui('编辑歌词 · {0}', [widget.audio.displayTitle]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge,
                            leading:
                                Icon(Symbols.lyrics, color: scheme.primary),
                            trailing: IconButton(
                                key: const ValueKey('lyric-editor-close'),
                                tooltip: ui('关闭'),
                                onPressed: saving ? null : _cancel,
                                icon: const Icon(Symbols.close))),
                        const SizedBox(height: 12),
                        Flexible(
                            child: AppScrollbar(
                                controller: _contentScroll,
                                child: SingleChildScrollView(
                                    controller: _contentScroll,
                                    key: const ValueKey(
                                        'lyric-editor-compact-scroll'),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                              '${widget.audio.artist} · ${widget.audio.album}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant)),
                                          _toolbar(theme, scheme),
                                          const SizedBox(height: 14),
                                          Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                for (final entry in {
                                                  0: '原文',
                                                  if (_hasAux) 1: '翻译',
                                                  if (_hasAux) 2: '注音',
                                                  if (_supportsPreview) 3: '预览'
                                                }.entries)
                                                  ChoiceChip(
                                                      key: ValueKey(
                                                          'lyric-editor-tab-${entry.key}'),
                                                      labelPadding:
                                                          MediaQuery.sizeOf(context)
                                                                      .width <
                                                                  600
                                                              ? const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 4)
                                                              : null,
                                                      visualDensity:
                                                          MediaQuery.sizeOf(context)
                                                                      .width <
                                                                  600
                                                              ? VisualDensity
                                                                  .compact
                                                              : null,
                                                      label:
                                                          Text(ui(entry.value)),
                                                      selected:
                                                          _tab == entry.key,
                                                      onSelected: _busy
                                                          ? null
                                                          : (_) => _selectTab(
                                                              entry.key)),
                                              ]),
                                          const SizedBox(height: 12),
                                          if (loading || loadingOnline)
                                            const LinearProgressIndicator(
                                                key: ValueKey(
                                                    'lyric-editor-online-progress')),
                                          if (loadError != null ||
                                              onlineError != null)
                                            Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 12),
                                                child: Text(
                                                    onlineError ?? loadError!,
                                                    key: const ValueKey(
                                                        'lyric-editor-online-error'),
                                                    style: TextStyle(
                                                        color: scheme.error))),
                                          if (_tab == 3)
                                            _preview(scheme)
                                          else ...[
                                            Text(
                                                ui(aux
                                                    ? '翻译和注音使用 LRC 时间戳，与原文行的开始时间一致。'
                                                    : '格式示例（时间可手动修改）'),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant)),
                                            const SizedBox(height: 6),
                                            if (!aux &&
                                                format !=
                                                    LyricEditFormat.lossless &&
                                                format != LyricEditFormat.plain)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 10),
                                                  child: SelectableText(
                                                      format.example,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                              color: scheme
                                                                  .primary))),
                                            TextField(
                                                key: ValueKey(_tab == 0
                                                    ? 'lyric-editor-field'
                                                    : 'lyric-editor-aux-$_tab'),
                                                controller: _activeController,
                                                focusNode: focusNode,
                                                minLines:
                                                    MediaQuery.sizeOf(context).width < 600
                                                        ? 4
                                                        : 8,
                                                maxLines: 16,
                                                readOnly: _busy,
                                                keyboardType:
                                                    TextInputType.multiline,
                                                onChanged: (_) => setState(
                                                    () => onlineError = null),
                                                style: theme.textTheme.bodyLarge
                                                    ?.copyWith(height: 1.5),
                                                decoration: InputDecoration(
                                                    filled: true,
                                                    fillColor: scheme
                                                        .surfaceContainerLowest,
                                                    border:
                                                        AppShape.inputBorder,
                                                    contentPadding:
                                                        const EdgeInsets.all(
                                                            16),
                                                    hintText: aux
                                                        ? '[00:01.000]…'
                                                        : format.example)),
                                          ],
                                        ])))),
                        IgnorePointer(
                            ignoring: _tab == 3,
                            child: AnimatedSwitcher(
                                key: const ValueKey(
                                    'lyric-editor-audition-collapse'),
                                duration: AppMotion.duration(context,
                                    MotionKind.layout, AppMotion.standard),
                                switchInCurve: AppMotion.standardCurve,
                                switchOutCurve: AppMotion.standardCurve,
                                transitionBuilder: (child, animation) =>
                                    SizeTransition(
                                        sizeFactor: animation,
                                        alignment: Alignment.topCenter,
                                        child: FadeTransition(
                                            opacity: animation, child: child)),
                                child: _tab == 3
                                    ? const SizedBox(
                                        key: ValueKey(
                                            'lyric-editor-audition-hidden'))
                                    : Padding(
                                        key: const ValueKey(
                                            'lyric-editor-audition-visible'),
                                        padding: const EdgeInsets.only(top: 12),
                                        child: _auditionControls(scheme)))),
                        const SizedBox(height: 16),
                        OverflowBar(
                            alignment: MainAxisAlignment.end,
                            spacing: 12,
                            overflowSpacing: 8,
                            children: [
                              TextButton.icon(
                                  onPressed: saving ? null : _cancel,
                                  icon: const Icon(Symbols.close),
                                  label: Text(ui('取消'))),
                              FilledButton.icon(
                                  key: const ValueKey('lyric-editor-save'),
                                  onPressed: _busy ? null : _save,
                                  icon: saving
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Symbols.save),
                                  label: Text(ui('保存编辑副本'))),
                            ]),
                      ])),
            )),
      ),
    );
  }
}

class _OnlineLyricCandidateDialog extends StatefulWidget {
  const _OnlineLyricCandidateDialog({
    required this.audio,
    required this.search,
    required this.loadCandidate,
    required this.customChoices,
    required this.loadCustomCandidate,
  });

  final Audio audio;
  final OnlineLyricEditorSearch search;
  final OnlineLyricEditorCandidateLoader loadCandidate;
  final List<CustomLyricSourceChoice> customChoices;
  final OnlineLyricEditorCustomCandidateLoader loadCustomCandidate;

  @override
  State<_OnlineLyricCandidateDialog> createState() =>
      _OnlineLyricCandidateDialogState();
}

class _OnlineLyricCandidateDialogState
    extends State<_OnlineLyricCandidateDialog> {
  final _candidateScroll = ScrollController();
  LyricSearchResponse? _response;
  String? _searchError;
  String? _loadingIdentity;
  final Map<String, String> _candidateErrors = <String, String>{};
  int _searchGeneration = 0;
  int _loadGeneration = 0;
  bool _searching = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    if (_searching || _closing) return;
    final generation = ++_searchGeneration;
    _loadGeneration++;
    setState(() {
      _searching = true;
      _searchError = null;
      _response = null;
      _loadingIdentity = null;
      _candidateErrors.clear();
    });
    try {
      final response = await widget.search(widget.audio);
      if (!mounted || _closing || generation != _searchGeneration) return;
      setState(() {
        _response = response;
        _searching = false;
      });
    } catch (error, trace) {
      LOGGER.e('[lyric editor] candidate search failed: $error',
          stackTrace: trace);
      if (!mounted || _closing || generation != _searchGeneration) return;
      setState(() {
        _searching = false;
        _searchError = ui("搜索歌词候选失败，请检查网络后重试。");
      });
    }
  }

  Future<void> _choose(SongSearchResult candidate) async {
    if (_loadingIdentity != null || _closing) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loadingIdentity = candidate.identity;
      _candidateErrors.remove(candidate.identity);
    });
    try {
      final lyric = await widget.loadCandidate(candidate);
      if (!mounted || _closing || generation != _loadGeneration) return;
      if (lyric == null || lyric.lines.isEmpty) {
        setState(() {
          _candidateErrors[candidate.identity] = ui(
            "{0}未返回可用歌词，可选择其他候选或重试。",
            [ui(candidate.sourceLabel)],
          );
        });
        return;
      }
      _complete(lyric);
    } catch (error, trace) {
      LOGGER.e('[lyric editor] candidate load failed: $error',
          stackTrace: trace);
      if (!mounted || _closing || generation != _loadGeneration) return;
      setState(() {
        _candidateErrors[candidate.identity] = ui("获取歌词失败，可选择其他候选或重试。");
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingIdentity = null);
      }
    }
  }

  Future<void> _chooseCustom(CustomLyricSourceChoice choice) async {
    if (_loadingIdentity != null || _closing) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loadingIdentity = choice.identity;
      _candidateErrors.remove(choice.identity);
    });
    try {
      final lyric = await widget.loadCustomCandidate(widget.audio, choice);
      if (!mounted || _closing || generation != _loadGeneration) return;
      if (lyric == null || lyric.lines.isEmpty) {
        setState(() {
          _candidateErrors[choice.identity] = ui(
            "{0}未返回可用歌词，可选择其他候选或重试。",
            [choice.profile.name],
          );
        });
        return;
      }
      _complete(lyric);
    } catch (error, trace) {
      LOGGER.e(
        '[lyric editor] custom candidate load failed: $error',
        stackTrace: trace,
      );
      if (!mounted || _closing || generation != _loadGeneration) return;
      setState(() {
        _candidateErrors[choice.identity] = ui("获取歌词失败，可选择其他候选或重试。");
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingIdentity = null);
      }
    }
  }

  void _invalidatePending() {
    if (_closing) return;
    _closing = true;
    _searchGeneration++;
    _loadGeneration++;
  }

  void _close() {
    if (_closing) return;
    _invalidatePending();
    Navigator.of(context).pop();
  }

  void _complete(Lyric lyric) {
    if (_closing) return;
    _invalidatePending();
    Navigator.of(context).pop(lyric);
  }

  @override
  void dispose() {
    _invalidatePending();
    _candidateScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dialogHeight =
        (MediaQuery.sizeOf(context).height - 64).clamp(360, 680).toDouble();
    return PopScope<Lyric>(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _invalidatePending();
      },
      child: Dialog(
        child: AppDialogContent(
          width: 660,
          maxHeight: dialogHeight,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale =
                    MediaQuery.textScalerOf(context).scale(14) / 14;
                final compact = constraints.maxHeight < 480 || textScale > 1.7;
                final candidateContent = DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: AppShape.surfaceRadius,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: ClipRRect(
                    borderRadius: AppShape.surfaceRadius,
                    child: _buildContent(context),
                  ),
                );
                final column = Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDialogTitle(
                      ui("填入联网歌词"),
                      style: theme.textTheme.titleLarge,
                      leading:
                          Icon(Symbols.cloud_download, color: scheme.primary),
                      trailing: IconButton(
                        key: const ValueKey('online-lyric-candidate-close'),
                        tooltip: ui("取消"),
                        onPressed: _close,
                        icon: const Icon(Symbols.close),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.audio.displayTitle} · ${widget.audio.artist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ui("选择一条候选歌词填入编辑器；填入后仍需手动保存。"),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (compact)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight:
                                (constraints.maxHeight * .68).clamp(0, 380)),
                        child: candidateContent,
                      )
                    else
                      Flexible(child: candidateContent),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        key: const ValueKey('online-lyric-candidate-cancel'),
                        onPressed: _close,
                        icon: const Icon(Symbols.close),
                        label: Text(ui("取消")),
                      ),
                    ),
                  ],
                );
                if (!compact) return column;
                return SingleChildScrollView(
                  key: const ValueKey('online-lyric-candidate-compact-scroll'),
                  child: column,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (widget.customChoices.isNotEmpty) {
      return _buildContentWithCustomChoices();
    }
    if (_searching) {
      return _OnlineCandidateState(
        key: const ValueKey('online-lyric-candidate-loading'),
        icon: const SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        message: ui("正在加载歌词"),
      );
    }
    if (_searchError != null) {
      return _OnlineCandidateState(
        key: const ValueKey('online-lyric-candidate-search-error'),
        icon: const Icon(Symbols.cloud_off),
        message: _searchError!,
        onRetry: _search,
      );
    }
    final response = _response;
    if (response == null) {
      return _OnlineCandidateState(
        icon: const Icon(Symbols.error),
        message: ui("候选状态不可用，请重试。"),
        onRetry: _search,
      );
    }
    if (response.sourcesDisabled) {
      return _OnlineCandidateState(
        key: const ValueKey('online-lyric-candidate-sources-disabled'),
        icon: const Icon(Symbols.cloud_off),
        message: ui("当前没有可用的联网歌词来源，请检查歌词与歌源设置。"),
      );
    }

    final failureText = response.failures.entries
        .map((entry) => '${ui(entry.key.sourceLabel)}：${ui(entry.value)}')
        .join('\n');
    if (response.candidates.isEmpty) {
      return _OnlineCandidateState(
        key: const ValueKey('online-lyric-candidate-empty'),
        icon: const Icon(Symbols.search_off),
        message: failureText.isEmpty
            ? ui("没有找到相关歌词候选，可检查歌曲标签后重试。")
            : ui("可用来源没有返回候选。"),
        details: failureText.isEmpty ? null : failureText,
        onRetry: _search,
      );
    }

    return AppScrollbar(
      controller: _candidateScroll,
      child: ListView.separated(
        controller: _candidateScroll,
        primary: false,
        shrinkWrap: true,
        key: const ValueKey('online-lyric-candidates'),
        padding: const EdgeInsets.all(10),
        itemCount: response.candidates.length + (failureText.isEmpty ? 0 : 1),
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          if (failureText.isNotEmpty && index == 0) {
            return _OnlineCandidateNotice(
              message: failureText,
              onRetry: _search,
            );
          }
          final candidateIndex = index - (failureText.isEmpty ? 0 : 1);
          return _candidateTile(response.candidates[candidateIndex]);
        },
      ),
    );
  }

  Widget _buildContentWithCustomChoices() {
    final response = _response;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 2),
        child: Text(
          ui("自定义歌源"),
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      for (final choice in widget.customChoices)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
          child: _customCandidateTile(choice),
        ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(height: 1),
      ),
    ];

    if (_searching) {
      children.add(
        ListTile(
          key: const ValueKey('online-lyric-candidate-loading'),
          leading: const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text(ui("正在加载歌词")),
        ),
      );
    } else if (_searchError != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(10),
          child: _OnlineCandidateNotice(
            message: _searchError!,
            onRetry: _search,
          ),
        ),
      );
    } else if (response == null) {
      children.add(
        ListTile(
          leading: const Icon(Symbols.error),
          title: Text(ui("候选状态不可用，请重试。")),
        ),
      );
    } else if (response.sourcesDisabled) {
      children.add(
        ListTile(
          key: const ValueKey('online-lyric-candidate-sources-disabled'),
          leading: const Icon(Symbols.cloud_off),
          title: Text(ui("内置歌词来源不可用；仍可选择上方的自定义歌源。")),
        ),
      );
    } else {
      final failureText = response.failures.entries
          .map((entry) => '${ui(entry.key.sourceLabel)}：${ui(entry.value)}')
          .join('\n');
      if (failureText.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.all(10),
            child: _OnlineCandidateNotice(
              message: failureText,
              onRetry: _search,
            ),
          ),
        );
      }
      if (response.candidates.isEmpty) {
        children.add(
          ListTile(
            key: const ValueKey('online-lyric-candidate-empty'),
            leading: const Icon(Symbols.search_off),
            title: Text(ui(failureText.isEmpty
                ? "没有找到相关歌词候选，可检查歌曲标签后重试。"
                : "可用来源没有返回候选。")),
          ),
        );
      } else {
        for (final candidate in response.candidates) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
              child: _candidateTile(candidate),
            ),
          );
        }
      }
    }

    return AppScrollbar(
      controller: _candidateScroll,
      child: ListView(
        controller: _candidateScroll,
        primary: false,
        shrinkWrap: true,
        key: const ValueKey('online-lyric-candidates'),
        children: children,
      ),
    );
  }

  Widget _candidateTile(SongSearchResult candidate) {
    final scheme = Theme.of(context).colorScheme;
    final loading = _loadingIdentity == candidate.identity;
    final error = _candidateErrors[candidate.identity];
    final details = [
      if (candidate.artists.trim().isNotEmpty) candidate.artists.trim(),
      if (candidate.album.trim().isNotEmpty) candidate.album.trim(),
    ].join(' · ');
    return Material(
      color: loading
          ? scheme.secondaryContainer.withValues(alpha: .72)
          : scheme.surfaceContainerLow,
      shape: AppShape.control,
      child: ListTile(
        key: ValueKey('online-lyric-candidate-${candidate.identity}'),
        enabled: _loadingIdentity == null,
        shape: AppShape.control,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text(switch (candidate.source) {
            ResultSource.qq => 'QQ',
            ResultSource.netease => ui("网"),
            ResultSource.kugou => ui("酷"),
            ResultSource.lrclib => 'LR',
          }),
        ),
        title: Text(
          candidate.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty)
              Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(candidate.scoreVerified
                ? ui("来源：{0} · 匹配 {1}%", [
                    ui(candidate.sourceLabel),
                    (candidate.score * 100).round(),
                  ])
                : ui('来源：{0} · 匹配度未知，仅供手动选择', [candidate.sourceLabel])),
            if (error != null)
              Text(error, style: TextStyle(color: scheme.error)),
          ],
        ),
        trailing: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Symbols.chevron_right),
        onTap: loading ? null : () => _choose(candidate),
      ),
    );
  }

  Widget _customCandidateTile(CustomLyricSourceChoice choice) {
    final scheme = Theme.of(context).colorScheme;
    final loading = _loadingIdentity == choice.identity;
    final error = _candidateErrors[choice.identity];
    return Material(
      color: loading
          ? scheme.secondaryContainer.withValues(alpha: .72)
          : scheme.surfaceContainerLow,
      shape: AppShape.control,
      child: ListTile(
        key: ValueKey('online-lyric-custom-${choice.profile.id}'),
        enabled: _loadingIdentity == null,
        shape: AppShape.control,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: const Icon(Symbols.api, size: 20),
        ),
        title: Text(
          choice.profile.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ui("来源：{0}", [ui("自定义歌源")])),
            if (error != null)
              Text(error, style: TextStyle(color: scheme.error)),
          ],
        ),
        trailing: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Symbols.chevron_right),
        onTap: loading ? null : () => _chooseCustom(choice),
      ),
    );
  }
}

class _OnlineCandidateState extends StatelessWidget {
  const _OnlineCandidateState({
    super.key,
    required this.icon,
    required this.message,
    this.details,
    this.onRetry,
  });

  final Widget icon;
  final String message;
  final String? details;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        heightFactor: 1,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(
                data: IconThemeData(
                  size: 34,
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: icon,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (details?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  details!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Symbols.refresh),
                  label: Text(ui("重试")),
                ),
              ],
            ],
          ),
        ),
      );
}

class _OnlineCandidateNotice extends StatelessWidget {
  const _OnlineCandidateNotice({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: AppShape.controlRadius,
      ),
      child: Row(
        children: [
          Icon(Symbols.warning, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Symbols.refresh),
            label: Text(ui("重试")),
          ),
        ],
      ),
    );
  }
}
