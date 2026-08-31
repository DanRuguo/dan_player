/// An absent preference follows the installed build's channel; an explicit
/// choice survives both upgrades and changing from a preview to a stable build.
class UpdateChannelPreference {
  const UpdateChannelPreference({this.receivePreviews});

  final bool? receivePreviews;

  factory UpdateChannelPreference.fromMap(Map map) {
    final value = map['ReceivePreviewUpdates'];
    return UpdateChannelPreference(
      receivePreviews: value is bool
          ? value
          : value == 0
              ? false
              : value == 1
                  ? true
                  : null,
    );
  }

  bool includesPreviewsFor(String version) =>
      receivePreviews ??
      RegExp(r'^[vV]?\d+\.\d+\.\d+(?:\.\d+)?-[0-9A-Za-z.-]+(?:\+[0-9A-Za-z.-]+)?$')
          .hasMatch(version.trim());

  Map<String, Object> toMap() => {
        if (receivePreviews != null) 'ReceivePreviewUpdates': receivePreviews!,
      };
}
