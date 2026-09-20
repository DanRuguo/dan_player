/// Font identity and fallback order shared by the main and lyric engines.
/// Keep the bundled family name aligned with the application's font manifest.
const String danEmbeddedFontFamily = "DanPingFangSC";

const List<String> danFontFamilyFallback = [
  danEmbeddedFontFamily,
  ".PingFang SC Regular",
  "PingFang SC Regular",
  "PingFang SC",
  "Noto Sans SC",
  "Noto Sans CJK SC",
  "Microsoft YaHei UI",
  "Microsoft YaHei",
  "SimHei",
  "Yu Gothic UI",
  "Malgun Gothic",
  "Segoe UI Symbol",
  "Segoe UI Emoji",
];
