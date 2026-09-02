import 'package:dan_player/app_settings.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Returns a display label without treating user-defined source names as
/// localization keys.
///
/// Built-in provider IDs are application-owned and can be translated. A
/// custom provider name is user data, so it must stay exactly as entered.
String onlineSourceDisplayLabel({
  required String? provider,
  required String fallback,
}) {
  final rawProvider = provider?.trim();
  if (rawProvider == null || rawProvider.isEmpty) return fallback;
  switch (rawProvider.toLowerCase()) {
    case 'qq':
      return ui('QQ音乐');
    case 'netease':
      return ui('网易云音乐');
  }

  final profileId = CustomMusicSourceProfile.profileIdFromProvider(rawProvider);
  if (profileId != null) {
    for (final profile in AppSettings.instance.customMusicSources.value) {
      if (profile.id == profileId) return profile.name;
    }
    return ui('自定义歌源');
  }
  return fallback;
}

/// Keeps a technical online identity useful at a glance without allowing an
/// opaque provider response to create a many-thousand-character detail row.
/// The full value remains available through the adjacent copy action.
String compactOnlineIdentity(
  String provider,
  String id, {
  int providerLimit = 28,
  int idLimit = 64,
}) =>
    '${_compactRunes(provider, providerLimit)} · ${_compactRunes(id, idLimit)}';

String _compactRunes(String value, int limit) {
  final runes = value.runes.toList(growable: false);
  if (runes.length <= limit || limit < 5) return value;
  final tailLength = (limit / 3).floor();
  final headLength = limit - tailLength - 1;
  return '${String.fromCharCodes(runes.take(headLength))}…'
      '${String.fromCharCodes(runes.skip(runes.length - tailLength))}';
}

class OnlineIdentitySummary extends StatelessWidget {
  const OnlineIdentitySummary({
    super.key,
    required this.provider,
    required this.id,
  });

  final String provider;
  final String id;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final fullIdentity = '$provider · $id';
    return Row(
      children: [
        Expanded(
          child: Text(
            compactOnlineIdentity(provider, id),
            key: const ValueKey('online-identity-summary'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('online-identity-copy'),
          tooltip: ui('复制完整联网标识'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: fullIdentity));
            if (context.mounted) {
              showTextOnSnackBar('已复制联网标识', context: context);
            }
          },
          icon: const Icon(Symbols.content_copy),
        ),
      ],
    );
  }
}
