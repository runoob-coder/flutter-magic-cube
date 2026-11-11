import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

const int kLogoArgb = 0xFFFF6A00;

/// Four quadrants detect both horizontal mirroring and vertical flipping.
const int kOrangeArgb = 0xFFFF6A00;
const int kGreenArgb = 0xFF00C853;
const int kBlueArgb = 0xFF2979FF;
const int kPurpleArgb = 0xFFAA00FF;

/// Build from raw pixels: a second toImage() call in the same test hangs
/// in this environment, so the suite records only one Picture.
Future<ui.Image> _solidLogo(int side) {
  final Uint8List pixels = Uint8List(side * side * 4);
  for (int i = 0; i < side * side; i++) {
    pixels[i * 4] = (kLogoArgb >> 16) & 0xFF;
    pixels[i * 4 + 1] = (kLogoArgb >> 8) & 0xFF;
    pixels[i * 4 + 2] = kLogoArgb & 0xFF;
    pixels[i * 4 + 3] = 0xFF;
  }
  return _decode(pixels, side, side);
}

Future<ui.Image> _quadrantLogo(int side) {
  final Uint8List pixels = Uint8List(side * side * 4);
  for (int y = 0; y < side; y++) {
    for (int x = 0; x < side; x++) {
      final bool right = x >= side ~/ 2;
      final bool bottom = y >= side ~/ 2;
      final int argb = switch ((right, bottom)) {
        (false, false) => kOrangeArgb,
        (true, false) => kGreenArgb,
        (false, true) => kBlueArgb,
        (true, true) => kPurpleArgb,
      };
      final int offset = (y * side + x) * 4;
      pixels[offset] = (argb >> 16) & 0xFF;
      pixels[offset + 1] = (argb >> 8) & 0xFF;
      pixels[offset + 2] = argb & 0xFF;
      pixels[offset + 3] = 0xFF;
    }
  }
  return _decode(pixels, side, side);
}

Future<ui.Image> _decode(Uint8List pixels, int width, int height) {
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

void main() {
  test('logo 只画在指定面的中心块上，并且跟着那一块转动', () async {
    const ui.Size view = ui.Size(300, 300);
    const int cell = 310;
    final ui.Image logo = await _solidLogo(64);
    final ui.Image quadrant = await _quadrantLogo(64);

    CubeScene buildScene(
      CubeState state, {
      double yaw = MagicCubeController.defaultYaw,
      double pitch = MagicCubeController.defaultPitch,
    }) => CubeScene(
      state: state,
      turn: null,
      yaw: yaw,
      pitch: pitch,
      viewport: view,
    );

    // Variants: 0 plain, 1 logo, 2 logo after an M turn, 3 oblique view,
    // 4 quadrant logo (orientation check).
    final CubeState plainState = CubeState();
    final CubeState logoState = CubeState();
    final CubeState turnedState = CubeState()..applyMove(CubeMove.parse('M'));
    final CubeState obliqueState = CubeState();
    final CubeState orientedState = CubeState();

    final CubeScene plain = buildScene(plainState);
    final CubeScene withLogo = buildScene(logoState);
    final CubeScene turned = buildScene(turnedState);
    final CubeScene oblique = buildScene(obliqueState, yaw: 0.6, pitch: 0.5);
    final CubeScene oriented = buildScene(orientedState);

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawPaint(ui.Paint()..color = const ui.Color(0xFF202020));
    const CubeTheme plainTheme = CubeTheme();
    final CubeTheme logoTheme = CubeTheme(centerLogo: logo);
    final CubeTheme quadrantTheme = CubeTheme(centerLogo: quadrant);
    const int variants = 5;
    for (int i = 0; i < variants; i++) {
      canvas.save();
      canvas.translate((i * cell).toDouble(), 0);
      CubePainter(
        scene: <CubeScene>[plain, withLogo, turned, oblique, oriented][i],
        theme: switch (i) {
          0 => plainTheme,
          4 => quadrantTheme,
          _ => logoTheme,
        },
      ).paint(canvas, view);
      canvas.restore();
    }

    final ui.Image image = await recorder.endRecording().toImage(
      cell * variants,
      cell,
    );
    final ByteData? raw = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final Uint8List pixels = raw!.buffer.asUint8List();

    final int width = cell * variants;
    ui.Color sampleAt(Offset p, int variant) {
      final int x = (p.dx + variant * cell).round().clamp(0, width - 1);
      final int y = p.dy.round().clamp(0, cell - 1);
      final int offset = (y * width + x) * 4;
      return ui.Color.fromARGB(
        255,
        pixels[offset],
        pixels[offset + 1],
        pixels[offset + 2],
      );
    }

    bool isLogoOrange(ui.Color c) => c.r > 0.5 && c.r > c.g * 1.6 && c.g > c.b;
    bool isNearWhite(ui.Color c) =>
        (c.r - c.g).abs() < 0.1 && (c.g - c.b).abs() < 0.1 && c.r > 0.55;

    Offset centerStickerOf(CubeScene scene) {
      final int index = scene.state.centerCubieIndices[kFaceUp];
      expect(index, isNot(-1), reason: '找不到 U 面中心块');
      final SceneFace face = scene.drawOrder.firstWhere(
        (SceneFace f) => f.cubieIndex == index && f.sticker == kFaceUp,
        orElse: () => fail('U 面中心块的贴纸不在可见面里'),
      );
      return scene.project(face.worldCenter);
    }

    final ui.Color plainCenter = sampleAt(centerStickerOf(plain), 0);
    expect(
      isNearWhite(plainCenter),
      isTrue,
      reason: '未配置 logo 时中心贴纸应当是白色，实际 $plainCenter',
    );

    final ui.Color logoCenter = sampleAt(centerStickerOf(withLogo), 1);
    expect(
      isLogoOrange(logoCenter),
      isTrue,
      reason: 'logo 没有画到中心贴纸上，实际 $logoCenter',
    );

    final int centerIndex = logoState.centerCubieIndices[kFaceUp];
    final SceneFace neighbour = withLogo.drawOrder.firstWhere(
      (SceneFace f) => f.sticker == kFaceUp && f.cubieIndex != centerIndex,
    );
    final ui.Color neighbourColor = sampleAt(
      withLogo.project(neighbour.worldCenter),
      1,
    );
    expect(
      isNearWhite(neighbourColor),
      isTrue,
      reason: '同一面的其它贴纸被误盖了 logo，实际 $neighbourColor',
    );

    final ui.Color movedCenter = sampleAt(centerStickerOf(turned), 2);
    expect(
      isLogoOrange(movedCenter),
      isTrue,
      reason: '转动之后 logo 没有跟着中心块，实际 $movedCenter',
    );

    // Perspective is verified via per-row edge drift: an axis-aligned
    // bounding box keeps row bounds fixed, while a real homography shifts
    // them by 20+ pixels at this view angle.
    int orange = 0;
    int minX = 9999;
    int maxX = -1;
    int minY = 9999;
    int maxY = -1;
    for (int y = 52; y < 72; y++) {
      for (int x = 125; x < 175; x++) {
        if (!isLogoOrange(sampleAt(Offset(x + 0.5, y + 0.5), 3))) continue;
        orange++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    expect(orange, greaterThan(50), reason: '斜视下几乎没有看到 logo');

    final List<int> rowMins = <int>[];
    final List<int> rowMaxs = <int>[];
    for (int y = minY; y <= maxY; y++) {
      int rowMin = 9999;
      int rowMax = -1;
      for (int x = minX; x <= maxX; x++) {
        if (!isLogoOrange(sampleAt(Offset(x + 0.5, y + 0.5), 3))) continue;
        if (x < rowMin) rowMin = x;
        if (x > rowMax) rowMax = x;
      }
      if (rowMin > rowMax) continue;
      rowMins.add(rowMin);
      rowMaxs.add(rowMax);
    }
    expect(rowMins.length, greaterThan(4), reason: 'logo 的有效行数太少');

    int spread(List<int> values) {
      int low = values.first;
      int high = values.first;
      for (final int value in values) {
        if (value < low) low = value;
        if (value > high) high = value;
      }
      return high - low;
    }

    final int leftSpread = spread(rowMins);
    final int rightSpread = spread(rowMaxs);
    expect(
      leftSpread > 8 || rightSpread > 8,
      isTrue,
      reason:
          'logo 没有跟着贴纸的透视倾斜'
          '（每行左边界只移动 $leftSpread 像素，右边界 $rightSpread 像素）',
    );

    // Image y grows downward while +v projects upward; a naive mapping
    // flips the logo vertically.
    final int orientedIndex = orientedState.centerCubieIndices[kFaceUp];
    final SceneFace orientedFace = oriented.drawOrder.firstWhere(
      (SceneFace f) => f.cubieIndex == orientedIndex && f.sticker == kFaceUp,
      orElse: () => fail('默认视角下看不到 U 面中心块'),
    );
    final double orientedStickerScale = quadrantTheme.stickerScale;
    final double orientedLogoScale = quadrantTheme.logoScale;
    final Offset orientedCenter = oriented.project(orientedFace.worldCenter);
    // su=-1 left, su=+1 right; sv=+1 up, sv=-1 down.
    Offset orientedCorner(double su, double sv) => oriented.project(
      orientedFace.worldCenter +
          orientedFace.worldU *
              (orientedStickerScale * orientedLogoScale * su) +
          orientedFace.worldV * (orientedStickerScale * orientedLogoScale * sv),
    );
    final Offset topLeft = orientedCorner(-1, 1);
    final Offset topRight = orientedCorner(1, 1);
    final Offset bottomLeft = orientedCorner(-1, -1);
    final Offset bottomRight = orientedCorner(1, -1);
    final Map<String, Offset> quadrantCenters = <String, Offset>{
      '左上（应为橙）': (topLeft + orientedCenter) / 2,
      '右上（应为绿）': (topRight + orientedCenter) / 2,
      '左下（应为蓝）': (bottomLeft + orientedCenter) / 2,
      '右下（应为紫）': (bottomRight + orientedCenter) / 2,
    };
    for (final MapEntry<String, Offset> entry in quadrantCenters.entries) {
      final ui.Color sampled = sampleAt(entry.value, 4);
      final bool matches = switch (entry.key) {
        '左上（应为橙）' => _isCloseTo(sampled, kOrangeArgb),
        '右上（应为绿）' => _isCloseTo(sampled, kGreenArgb),
        '左下（应为蓝）' => _isCloseTo(sampled, kBlueArgb),
        _ => _isCloseTo(sampled, kPurpleArgb),
      };
      expect(
        matches,
        isTrue,
        reason:
            'logo 的朝向不对：${entry.key}，采样点 ${entry.value}，'
            '实际颜色 $sampled',
      );
    }

    image.dispose();
    logo.dispose();
    quadrant.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}

bool _isCloseTo(ui.Color color, int argb) {
  final ui.Color target = ui.Color(argb);
  return (color.r - target.r).abs() < 0.12 &&
      (color.g - target.g).abs() < 0.12 &&
      (color.b - target.b).abs() < 0.12;
}
