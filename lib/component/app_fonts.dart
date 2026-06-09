import 'package:flutter/material.dart';

const String danCjkFontFamily = "SimHei";

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
  );
}
