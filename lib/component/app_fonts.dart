import 'package:desktop_lyric/app_fonts.dart';
import 'package:flutter/material.dart';

export 'package:desktop_lyric/app_fonts.dart';

const String danEmbeddedFontDisplayName = "Source Han Sans SC";
const String danCjkFontFamily = danEmbeddedFontFamily;

String danFontDisplayName(String? fontFamily) {
  final family = fontFamily?.trim();
  if (family == null ||
      family.isEmpty ||
      family == 'DanPingFangSC' ||
      family == danEmbeddedFontFamily) {
    return danEmbeddedFontDisplayName;
  }
  return family;
}

TextStyle danCjkTextStyle({
  String? fontFamily,
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
}) {
  return TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontFamily: fontFamily ?? danCjkFontFamily,
    fontFamilyFallback: danFontFamilyFallback,
  );
}
