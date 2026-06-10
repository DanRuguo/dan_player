import 'package:flutter/material.dart';

const String danEmbeddedFontFamily = "DanPingFangSC";
const String danEmbeddedFontDisplayName = ".PingFang SC Regular";
const String danCjkFontFamily = danEmbeddedFontFamily;

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
];

String danFontDisplayName(String? fontFamily) {
  final family = fontFamily?.trim();
  if (family == null || family.isEmpty || family == danEmbeddedFontFamily) {
    return danEmbeddedFontDisplayName;
  }
  return family;
}

TextStyle danCjkTextStyle({
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
}) {
  return TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontFamily: danCjkFontFamily,
    fontFamilyFallback: danFontFamilyFallback,
  );
}
