import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/page/settings_page/settings_busy_indicator.dart';
import 'package:dan_player/online/app_network_proxy.dart';
import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:dan_player/online/windows_system_proxy.dart';
import 'package:dan_player/utils.dart' show AppNoticeKind, showAppNotice;
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Network routing for requests made by the player. System and direct modes
/// apply on selection; custom proxy values remain drafts until saved.
class NetworkProxySettings extends StatefulWidget {
  const NetworkProxySettings(
      {super.key, this.preferences, this.persist, this.probe});

  final ValueNotifier<NetworkProxyPreferences>? preferences;
  final Future<void> Function()? persist;
  final Future<NetworkProxyProbeResult> Function(NetworkProxyPreferences)?
      probe;

  @override
  State<NetworkProxySettings> createState() => _NetworkProxySettingsState();
}

class _NetworkProxySettingsState extends State<NetworkProxySettings> {
  final _address = TextEditingController();
  final _port = TextEditingController();
  late NetworkProxyMode _mode;
  bool _dirty = false;
  bool _saving = false;
  bool _persistInFlight = false;
  bool _persistQueued = false;
  bool _retryNeeded = false;
  bool _applyingLocal = false;
  bool _testing = false;
  String? _error;
  String? _result;
  bool _testPassed = false;
  int _probeRevision = 0;
  int _commitRevision = 0;
  late Future<void> Function() _persist;

  ValueNotifier<NetworkProxyPreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.networkProxy;

  @override
  void initState() {
    super.initState();
    _persist = widget.persist ?? _persistSettings;
    _readSaved();
    _preferences.addListener(_onPreferencesChanged);
  }

  @override
  void didUpdateWidget(covariant NetworkProxySettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    _persist = widget.persist ?? _persistSettings;
    final previous = oldWidget.preferences ?? AppSettings.instance.networkProxy;
    if (!identical(previous, _preferences)) {
      previous.removeListener(_onPreferencesChanged);
      _preferences.addListener(_onPreferencesChanged);
      _readSaved();
    }
  }

  Future<void> _persistSettings() => AppSettings.instance.saveSettings(
      captureWindowSize: false, throwOnError: true, requireCommit: true);

  void _readSaved() {
    final value = _preferences.value;
    _mode = value.mode;
    _address.text = value.customProxyUrl ?? '';
    _port.clear();
    _dirty = false;
    _retryNeeded = false;
    _error = null;
    _result = null;
    _testing = false;
    _probeRevision++;
  }

  void _onPreferencesChanged() {
    if (_dirty || _applyingLocal || !mounted) return;
    setState(_readSaved);
  }

  void _edit() {
    setState(() {
      _dirty = true;
      _error = null;
      _result = null;
      _testing = false;
      _probeRevision++;
    });
  }

  bool get _hasUnsavedCustomDraft =>
      _address.text.trim() != (_preferences.value.customProxyUrl ?? '') ||
      _port.text.trim().isNotEmpty;

  void _selectMode(NetworkProxyMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _dirty = true;
      _error = null;
      _result = null;
      _testing = false;
      _probeRevision++;
    });
    if (mode != NetworkProxyMode.custom) {
      _applyAndPersist(NetworkProxyPreferences(
          mode: mode, customProxyUrl: _preferences.value.customProxyUrl));
    }
  }

  NetworkProxyPreferences? _candidate() {
    final saved = _preferences.value;
    if (_mode != NetworkProxyMode.custom) {
      return NetworkProxyPreferences(
          mode: _mode, customProxyUrl: saved.customProxyUrl);
    }
    final address = _address.text.trim();
    final portText = _port.text.trim();
    String input = address;
    if (portText.isNotEmpty) {
      final port = int.tryParse(portText);
      if (port == null || port < 1 || port > 65535) return null;
      final base =
          Uri.tryParse(address.contains('://') ? address : 'http://$address');
      if (base == null || base.host.isEmpty) return null;
      input = base.replace(port: port).toString();
    }
    final normalized = NetworkProxyPreferences.normalizeCustomProxy(input);
    if (normalized == null) return null;
    return NetworkProxyPreferences(
        mode: NetworkProxyMode.custom, customProxyUrl: normalized);
  }

  NetworkProxyPreferences? _validatedCandidate() {
    final candidate = _candidate();
    if (candidate == null) {
      setState(() {
        _error = ui('请输入有效的 HTTP 代理地址和端口。');
        _result = null;
      });
    }
    return candidate;
  }

  Future<void> _save() async {
    if (_saving || _mode != NetworkProxyMode.custom) return;
    final candidate = _validatedCandidate();
    if (candidate == null) return;
    _applyAndPersist(candidate);
  }

  void _applyAndPersist(NetworkProxyPreferences candidate) {
    setState(() {
      _saving = true;
      _retryNeeded = false;
      _error = null;
      _result = null;
      _testing = false;
      _probeRevision++;
    });
    _applyingLocal = true;
    try {
      _preferences.value = candidate;
    } finally {
      _applyingLocal = false;
    }
    // A user may have just changed the Windows proxy while this page was open.
    WindowsSystemProxy.instance.refresh();
    _commitRevision++;
    _persistQueued = true;
    unawaited(_drainPersistence());
  }

  void _retryPersist() {
    if (_saving || !_retryNeeded) return;
    setState(() {
      _saving = true;
      _retryNeeded = false;
      _error = null;
    });
    _persistQueued = true;
    unawaited(_drainPersistence());
  }

  Future<void> _drainPersistence() async {
    if (_persistInFlight) return;
    _persistInFlight = true;
    try {
      // One write at a time. If a selection changes during an older write,
      // persist the latest live preference again after that write finishes.
      while (_persistQueued) {
        _persistQueued = false;
        final revision = _commitRevision;
        try {
          await _persist();
        } catch (_) {
          if (revision != _commitRevision) continue;
          if (!mounted) {
            showAppNotice(ui('代理设置已在本次运行应用，但保存失败；请重试。'),
                kind: AppNoticeKind.error);
            return;
          }
          setState(() {
            _saving = false;
            _retryNeeded = true;
            _error = ui('代理设置已在本次运行应用，但保存失败；请重试。');
          });
          return;
        }
        if (!mounted || revision != _commitRevision) continue;
        setState(() {
          if (_mode == NetworkProxyMode.custom &&
              _preferences.value.mode == NetworkProxyMode.custom) {
            _address.text = _preferences.value.customProxyUrl ?? '';
            _port.clear();
          }
          // A hidden custom draft must not block updates to the active system
          // or direct mode from another settings owner.
          _dirty = _mode != _preferences.value.mode ||
              (_mode == NetworkProxyMode.custom && _hasUnsavedCustomDraft);
          _saving = false;
          _retryNeeded = false;
          _error = null;
          _result = ui('代理设置已应用并保存。');
          _testPassed = true;
        });
      }
    } finally {
      _persistInFlight = false;
      if (_persistQueued) unawaited(_drainPersistence());
    }
  }

  Future<void> _test() async {
    if (_testing) return;
    final candidate = _validatedCandidate();
    if (candidate == null) return;
    final revision = ++_probeRevision;
    setState(() {
      _testing = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await (widget.probe?.call(candidate) ??
          AppNetworkProxy.testGitHubConnectivity(preferences: candidate));
      if (!mounted || revision != _probeRevision) return;
      final elapsed = result.elapsed.inMilliseconds;
      setState(() {
        _testPassed = result.reachable;
        _result = result.error == 'system_pac_unsupported'
            ? ui(
                '自动代理脚本暂不能用于应用内 HTTP 请求；请使用自定义代理。原生在线播放和 FFmpeg 可继续跟随 Windows 代理。')
            : result.reachable && result.statusCode == 200
                ? ui('GitHub 连接成功（HTTP {0}，{1} 毫秒）。',
                    [result.statusCode ?? 0, elapsed])
                : result.reachable && result.statusCode != null
                    ? ui('已连接 GitHub，但接口返回 HTTP {0}（{1} 毫秒）。',
                        [result.statusCode, elapsed])
                    : result.statusCode != null
                        ? ui('GitHub 连接失败（HTTP {0}，{1} 毫秒）。',
                            [result.statusCode, elapsed])
                        : ui('GitHub 连接失败或超时（{0} 毫秒）。', [elapsed]);
      });
    } catch (_) {
      if (!mounted || revision != _probeRevision) return;
      setState(() {
        _testPassed = false;
        _result = ui('GitHub 连接测试失败，请检查代理设置后重试。');
      });
    } finally {
      if (mounted && revision == _probeRevision) {
        setState(() => _testing = false);
      }
    }
  }

  @override
  void dispose() {
    _probeRevision++;
    _preferences.removeListener(_onPreferencesChanged);
    _address.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(
            title: ui('网络代理'),
            icon: Icons.router_outlined,
            subtitle: ui('播放器的联网请求使用此设置；外部浏览器仍使用浏览器自己的网络设置。'),
          ),
          const SizedBox(height: 14),
          AppSegmentedControl<NetworkProxyMode>(
            key: const ValueKey('network-proxy-mode'),
            semanticLabel: ui('网络代理模式'),
            value: _mode,
            onChanged: _selectMode,
            options: [
              AppSegmentOption(
                  value: NetworkProxyMode.system,
                  label: ui('系统代理'),
                  icon: Icons.settings_suggest_outlined),
              AppSegmentOption(
                  value: NetworkProxyMode.direct,
                  label: ui('直连'),
                  icon: Icons.link_outlined),
              AppSegmentOption(
                  value: NetworkProxyMode.custom,
                  label: ui('自定义 HTTP 代理'),
                  icon: Icons.tune_outlined),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _mode == NetworkProxyMode.system
                ? ui('使用 Windows 当前静态代理，未配置时直连；自动代理脚本请改用自定义 HTTP 代理。')
                : _mode == NetworkProxyMode.direct
                    ? ui('播放器直接连接，不经过系统或自定义代理。')
                    : ui('填写代理主机或完整 HTTP 链接和端口，例如 127.0.0.1 与 7890。'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (_mode == NetworkProxyMode.custom) ...[
            const SizedBox(height: 14),
            LayoutBuilder(builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final addressField = TextField(
                key: const ValueKey('network-proxy-address'),
                controller: _address,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (_) => _edit(),
                decoration: InputDecoration(
                    labelText: ui('代理地址或链接'),
                    hintText: 'http://127.0.0.1:7890',
                    border: AppShape.inputBorder),
              );
              final portField = TextField(
                key: const ValueKey('network-proxy-port'),
                controller: _port,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _edit(),
                decoration: InputDecoration(
                    labelText: ui('代理端口'),
                    hintText: '7890',
                    border: AppShape.inputBorder),
              );
              return stacked
                  ? Column(children: [
                      addressField,
                      const SizedBox(height: 12),
                      portField,
                    ])
                  : Row(children: [
                      Expanded(flex: 3, child: addressField),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: portField),
                    ]);
            }),
            const SizedBox(height: 6),
            Text(ui('地址已包含端口时，端口输入框可留空。'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('network-proxy-test'),
                onPressed:
                    _testing || _saving ? null : () => unawaited(_test()),
                icon: _testing
                    ? const SettingsBusyIndicator.circular(size: 16)
                    : const Icon(Icons.network_check_outlined),
                label: Text(ui('测试 GitHub 连接')),
              ),
              AnimatedSwitcher(
                key: const ValueKey('network-proxy-save-transition'),
                duration: AppMotion.duration(
                    context, MotionKind.layout, AppMotion.standard),
                switchInCurve: AppMotion.standardCurve,
                switchOutCurve: AppMotion.standardCurve,
                transitionBuilder: (child, animation) => SizeTransition(
                  axis: Axis.horizontal,
                  alignment: Alignment.centerRight,
                  sizeFactor: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: _mode == NetworkProxyMode.custom
                    ? FilledButton.icon(
                        key: const ValueKey('network-proxy-save'),
                        onPressed: _saving ? null : () => unawaited(_save()),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(ui('保存并应用')),
                      )
                    : _retryNeeded
                        ? FilledButton.icon(
                            key: const ValueKey('network-proxy-retry'),
                            onPressed: _saving ? null : _retryPersist,
                            icon: const Icon(Icons.refresh_outlined),
                            label: Text(ui('重试保存')),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('network-proxy-save-hidden')),
              ),
            ],
          ),
          if (_error != null || _result != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                _error ?? _result!,
                key: const ValueKey('network-proxy-feedback'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _error != null || !_testPassed
                        ? scheme.error
                        : scheme.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
