import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/page/settings_page/settings_busy_indicator.dart';
import 'package:dan_player/src/rust/api/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _registerUrl = 'https://e.developer.yahoo.co.jp/register';
const _attributionUrl = 'https://developer.yahoo.co.jp/sitemap/';

/// Edits local credentials only. Opening, saving and clearing this form do not
/// inspect the dictionary or initiate an online reading request.
class JapaneseOnlineReadingSettings extends StatefulWidget {
  const JapaneseOnlineReadingSettings(
      {super.key, this.preferences, this.persist, this.openUrl});

  final ValueNotifier<JapaneseReadingPreferences>? preferences;
  final Future<void> Function()? persist;
  final Future<void> Function(String)? openUrl;

  @override
  State<JapaneseOnlineReadingSettings> createState() =>
      _JapaneseOnlineReadingSettingsState();
}

class _JapaneseOnlineReadingSettingsState
    extends State<JapaneseOnlineReadingSettings> {
  GlobalKey<_CredentialsDialogState>? _dialog;
  ValueNotifier<bool>? _available;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!SettingsSectionVisibility.isVisibleOf(context)) _leave();
  }

  @override
  void didUpdateWidget(JapaneseOnlineReadingSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.preferences, oldWidget.preferences)) _leave();
  }

  void _leave() {
    _available?.value = false;
    final route = _dialog?.currentState?.route;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator == null || !navigator.mounted) return;
      if (route.isCurrent) {
        navigator.pop();
      } else if (route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  Future<void> _open() async {
    if (_dialog != null || !SettingsSectionVisibility.isVisibleOf(context)) {
      return;
    }
    final key = GlobalKey<_CredentialsDialogState>();
    final available = _available = ValueNotifier(true);
    final preferences =
        widget.preferences ?? AppSettings.instance.japaneseReadings;
    final persist = widget.persist ??
        () => AppSettings.instance
            .saveSettings(throwOnError: true, captureWindowSize: false);
    final openUrl = widget.openUrl ?? (String url) => launchInBrowser(uri: url);
    setState(() => _dialog = key);
    try {
      await showAppDialog<void>(
          context: context,
          builder: (_) => _CredentialsDialog(
              key: key,
              preferences: preferences,
              persist: persist,
              openUrl: openUrl,
              available: available));
    } finally {
      available.value = false;
      available.dispose();
      if (identical(_dialog, key)) {
        _available = null;
        if (mounted) {
          setState(() => _dialog = null);
        } else {
          _dialog = null;
        }
      }
    }
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
        child: SettingsTile(
            surface: false,
            icon: Icons.cloud_outlined,
            description: ui('联网假名注音'),
            subtitle: ui('需要您自己的 Yahoo! JAPAN Client ID；自动联网开启时优先使用，失败时回退离线。'),
            action: OutlinedButton.icon(
                key: const ValueKey('japanese-online-configure'),
                onPressed: _dialog == null &&
                        SettingsSectionVisibility.isVisibleOf(context)
                    ? _open
                    : null,
                icon: const Icon(Icons.cloud_outlined),
                label: Text(ui('配置联网注音')))));
  }
}

class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog(
      {super.key,
      required this.preferences,
      required this.persist,
      required this.openUrl,
      required this.available});
  final ValueNotifier<JapaneseReadingPreferences> preferences;
  final Future<void> Function() persist;
  final Future<void> Function(String) openUrl;
  final ValueNotifier<bool> available;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  late final TextEditingController _input;
  ModalRoute<void>? route;
  Animation<double>? _animation;
  bool _closed = false,
      _saving = false,
      _obscured = true,
      _updateQueued = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input =
        TextEditingController(text: widget.preferences.value.yahooClientId);
    widget.available.addListener(_availabilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of<void>(context);
    final animation = route?.animation;
    if (!identical(animation, _animation)) {
      _animation?.removeStatusListener(_statusChanged);
      _animation = animation;
      _animation?.addStatusListener(_statusChanged);
    }
    if (_animation?.status == AnimationStatus.reverse) beginExit();
    if (!widget.available.value) {
      beginExit();
      final captured = route;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = captured?.navigator;
        if (navigator == null || !navigator.mounted) return;
        if (captured!.isCurrent) {
          navigator.pop();
        } else if (captured.isActive) {
          navigator.removeRoute(captured);
        }
      });
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse) beginExit();
  }

  void _availabilityChanged() {
    if (!widget.available.value) beginExit();
  }

  void beginExit() {
    if (_closed) return;
    _closed = true;
    widget.available.value = false;
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_updateQueued) return;
      _updateQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateQueued = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _close() {
    if (_closed) return;
    beginExit();
    final navigator = route?.navigator;
    if (navigator == null) return;
    if (route!.isCurrent) {
      navigator.pop();
    } else if (route!.isActive) {
      navigator.removeRoute(route!);
    }
  }

  Future<void> _save() async {
    if (_closed || _saving || !widget.available.value) return;
    final value = normalizeJapaneseReadingClientId(_input.text);
    if (value == null) {
      setState(() => _error = 'Client ID 只能包含不带空格的 ASCII 字符，最多 2048 个字符。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.preferences.value =
        widget.preferences.value.copyWith(yahooClientId: value);
    try {
      await widget.persist();
      if (!mounted || _closed || !widget.available.value) return;
      if (widget.preferences.value.yahooClientId != value) {
        // A newer credential wins. Keep the form available for an explicit
        // retry instead of closing a newer route or reapplying an old value.
        setState(() => _saving = false);
        return;
      }
      _close();
    } catch (_) {
      if (!mounted || _closed || !widget.available.value) return;
      setState(() {
        _saving = false;
        _error = '联网注音设置保存失败；当前输入已保留，请重试。';
      });
    }
  }

  Future<void> _link(String url) async {
    if (_closed) return;
    try {
      await widget.openUrl(url);
    } catch (_) {
      if (mounted && !_closed) {
        showPresentationNotice(ui('无法打开网页，请复制链接后重试。'),
            context: context, kind: AppNoticeKind.error);
      }
    }
  }

  @override
  void dispose() {
    widget.available.removeListener(_availabilityChanged);
    _animation?.removeStatusListener(_statusChanged);
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    return TickerMode(
        enabled: !_closed,
        child: Dialog(
            key: const ValueKey('japanese-online-dialog'),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: AppDialogContent(
                width: 560,
                maxHeight: 680,
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: AppDialogResize(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      AppDialogTitle(ui('联网假名注音'),
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Flexible(
                          child: SingleChildScrollView(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                            Text(ui(
                                '需要您自己的 Yahoo! JAPAN Client ID；自动联网开启时优先使用，失败时回退离线。')),
                            const SizedBox(height: 16),
                            Text(ui('Yahoo! JAPAN Client ID'),
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 6),
                            Semantics(
                              label: ui('Yahoo! JAPAN Client ID'),
                              child: TextField(
                                  key: const ValueKey(
                                      'japanese-online-client-id'),
                                  controller: _input,
                                  obscureText: _obscured,
                                  enabled: !_closed && !_saving,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: InputDecoration(
                                      hintText: 'Client ID',
                                      suffixIcon: IconButton(
                                          key: const ValueKey(
                                              'japanese-online-visibility'),
                                          tooltip: ui(_obscured
                                              ? '显示 Client ID'
                                              : '隐藏 Client ID'),
                                          onPressed: _closed || _saving
                                              ? null
                                              : () => setState(
                                                  () => _obscured = !_obscured),
                                          icon: Icon(_obscured
                                              ? Icons.visibility_outlined
                                              : Icons
                                                  .visibility_off_outlined))),
                                  onSubmitted: (_) => unawaited(_save())),
                            ),
                            const SizedBox(height: 8),
                            Text(ui('仅保存在本机，用于您主动或允许的日语假名请求。'),
                                style: theme.textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton.icon(
                                    key: const ValueKey(
                                        'japanese-online-register'),
                                    onPressed: _closed
                                        ? null
                                        : () => _link(_registerUrl),
                                    icon: const Icon(Icons.open_in_new),
                                    label: Text(ui('申请 Client ID')))),
                            Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton(
                                    key: const ValueKey(
                                        'japanese-online-attribution'),
                                    onPressed: _closed
                                        ? null
                                        : () => _link(_attributionUrl),
                                    child: const Text(
                                        'Web Services by Yahoo! JAPAN'))),
                            if (_saving) ...[
                              const SizedBox(height: 12),
                              const SettingsBusyIndicator.linear(),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Semantics(
                                  liveRegion: true,
                                  child: Text(ui(_error!),
                                      key: const ValueKey(
                                          'japanese-online-error'),
                                      style: TextStyle(
                                          color: theme.colorScheme.error))),
                            ],
                          ]))),
                      const SizedBox(height: 16),
                      AppDialogActions(children: [
                        TextButton.icon(
                            key: const ValueKey('japanese-online-cancel'),
                            onPressed: _closed ? null : _close,
                            icon: const Icon(Icons.close),
                            label: Text(ui('取消'))),
                        TextButton.icon(
                            key: const ValueKey('japanese-online-clear'),
                            onPressed: _closed || _saving
                                ? null
                                : () {
                                    _input.clear();
                                    setState(() => _error = null);
                                  },
                            icon: const Icon(Icons.delete_outline),
                            label: Text(ui('清除'))),
                        FilledButton.icon(
                            key: const ValueKey('japanese-online-save'),
                            onPressed: _closed || _saving ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(ui('保存'))),
                      ]),
                    ]))))));
  }
}
