import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show IconData;

void _checkImageSize(double size) {
  if (!size.isFinite || size <= 0) {
    throw ArgumentError.value(
      size,
      'size',
      'Output image size must be a finite positive number',
    );
  }
}

/// Renders text into a square, transparent image. The caller owns and must
/// dispose the returned ui.Image.
Future<ui.Image> renderTextToImage(
  String text, {
  double size = 256,
  Color color = const Color(0xFFFFFFFF),
  TextDirection direction = .ltr,
  String? fontFamily,
  String? fontPackage,
}) async {
  _checkImageSize(size);
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontFamily: fontFamily,
        package: fontPackage,
      ),
    ),
    textDirection: direction,
  )..layout();

  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  // Center by the glyph box, not the font line height, so the visual
  // center lands in the middle of the image.
  painter.paint(
    canvas,
    Offset((size - painter.width) / 2, (size - painter.height) / 2),
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(size.toInt(), size.toInt());
  picture.dispose();
  painter.dispose();
  return image;
}

Future<ui.Image> renderIconToImage(
  IconData icon, {
  double size = 256,
  Color color = const Color(0xFFFFFFFF),
  TextDirection direction = .ltr,
}) {
  _checkImageSize(size);
  return renderTextToImage(
    String.fromCharCode(icon.codePoint),
    fontFamily: icon.fontFamily,
    fontPackage: icon.fontPackage,
    size: size,
    color: color,
    direction: direction,
  );
}

/// Vector-drawn, so it renders even without the icon font (font glyphs
/// would silently come out blank). The caller owns and must dispose the
/// returned ui.Image.
Future<ui.Image> renderFlutterLogoToImage({
  double size = 256,
  FlutterLogoStyle style = .markOnly,
  Color? textColor,
}) async {
  _checkImageSize(size);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  final BoxPainter painter = FlutterLogoDecoration(
    style: style,
    textColor: textColor ?? const Color(0xFF61687D),
  ).createBoxPainter(() {});
  painter.paint(canvas, .zero, ImageConfiguration(size: .square(size)));
  painter.dispose();
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(size.toInt(), size.toInt());
  picture.dispose();
  return image;
}
