import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

/// Raw pixels avoid a second toImage() call, which hangs in this
/// environment.
Future<ui.Image> _solidLogo(int side, int argb) {
  final Uint8List pixels = Uint8List(side * side * 4);
  for (int i = 0; i < side * side; i++) {
    pixels[i * 4] = (argb >> 16) & 0xFF;
    pixels[i * 4 + 1] = (argb >> 8) & 0xFF;
    pixels[i * 4 + 2] = argb & 0xFF;
    pixels[i * 4 + 3] = 0xFF;
  }
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    side,
    side,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  test('withLogo 覆盖传入的字段，未传的沿用原值', () async {
    final ui.Image logo = await _solidLogo(64, 0xFFFF6A00);
    const CubeTheme base = CubeTheme(logoFace: kFaceRight, logoScale: 0.4);

    final CubeTheme updated = base.withLogo(centerLogo: logo, logoScale: 0.9);

    expect(updated.centerLogo, same(logo));
    expect(updated.logoFace, kFaceRight, reason: '未传的字段应沿用原值');
    expect(updated.logoScale, 0.9);
    expect(base.centerLogo, isNull);
    expect(base.logoScale, 0.4);
  });

  test('withLogo 三个参数全为 null 时返回同一个对象', () {
    const CubeTheme base = CubeTheme();
    expect(base.withLogo(), same(base));
    expect(
      base.withLogo(centerLogo: null, logoFace: null, logoScale: null),
      same(base),
    );
  });

  test('withLogo 只传 logoFace 也能生效', () async {
    final ui.Image logo = await _solidLogo(64, 0xFF2979FF);
    final CubeTheme base = CubeTheme(centerLogo: logo, logoScale: 0.62);

    final CubeTheme updated = base.withLogo(logoFace: kFaceFront);
    expect(updated.centerLogo, same(logo));
    expect(updated.logoFace, kFaceFront);
    expect(updated.logoScale, 0.62);
  });

  // No widget-level logo test here: pumping MagicCube with clipPath +
  // drawImageRect hangs in this environment; offscreen recording in
  // center_logo_test.dart covers the actual drawing.
}
