/// Language roles cannot be inferred from duplicate timestamps alone.
enum LocalLyricLineOrder {
  automatic,
  originalTranslationRomanization,
  romanizationOriginalTranslation;

  static LocalLyricLineOrder decode(Object? value) =>
      values.where((item) => item.name == value).firstOrNull ?? automatic;
}

enum NowPlayingProgressStyle {
  standard,
  waveform;

  static NowPlayingProgressStyle decode(Object? value) =>
      values.where((item) => item.name == value).firstOrNull ?? standard;
}

enum WaveformBarDensity {
  automatic,
  sparse,
  medium,
  dense;

  static WaveformBarDensity decode(Object? value) =>
      values.where((item) => item.name == value).firstOrNull ?? automatic;
}
