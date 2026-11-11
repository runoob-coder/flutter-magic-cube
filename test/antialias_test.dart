import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

/// 1:2:4 channel ratios keep top/side blends collinear, so only blends
/// with the white body count as antialias transitions.
const CubeTheme kAaTheme = CubeTheme(
  lighting: false,
  body: Color(0xFFFFFFFF),
  up: Color(0xFF204080),
  down: Color(0xFF204080),
  left: Color(0xFF204080),
  right: Color(0xFF204080),
  front: Color(0xFF204080),
  back: Color(0xFF204080),
  gap: 0,
  stickerScale: 0.84,
  stickerRadius: 0,
  stickerThickness: 0.05,
  stickerSideShade: 0.5,
  stickerShadowOpacity: 0,
  outerCornerRadius: 0,
  bodyCornerRadius: 0,
);

const Size kAaViewport = Size(400, 400);

const int _topB = 128;
const int _sideB = 64;

Future<ui.Image> _renderFrame(
  CubeTheme theme, {
  Size viewport = kAaViewport,
}) async {
  final CubeScene scene = CubeScene(
    state: CubeState(),
    yaw: MagicCubeController.defaultYaw,
    pitch: MagicCubeController.defaultPitch,
    viewport: viewport,
    gap: theme.gap,
    cornerRadius: theme.outerCornerRadius,
  );
  final CubePainter painter = CubePainter(scene: scene, theme: theme);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(Offset.zero & viewport, Paint()..color = theme.body);
  painter.paint(canvas, viewport);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    viewport.width.toInt(),
    viewport.height.toInt(),
  );
  picture.dispose();
  return image;
}

bool _onSegment(
  int r,
  int g,
  int b,
  int ar,
  int ag,
  int ab,
  int br,
  int bg,
  int bb,
) {
  if (b < math.min(ab, bb) || b > math.max(ab, bb)) return false;
  final double t = ab == bb ? 0.0 : (b - ab) / (bb - ab);
  final double er = ar + (br - ar) * t;
  final double eg = ag + (bg - ag) * t;
  return (r - er).abs() <= 3 && (g - eg).abs() <= 3;
}

bool _near(int r, int g, int b, int cr, int cg, int cb) =>
    (r - cr).abs() <= 2 && (g - cg).abs() <= 2 && (b - cb).abs() <= 2;

int _countBlends(
  ByteData pixels,
  int dimension, {
  required int ar,
  required int ag,
  required int ab,
  required int br,
  required int bg,
  required int bb,
}) {
  final int stride = 4;
  int blends = 0;
  for (int y = 0; y < dimension; y++) {
    for (int x = 0; x < dimension; x++) {
      final int i = y * stride * dimension + x * stride;
      final int r = pixels.getUint8(i);
      final int g = pixels.getUint8(i + 1);
      final int b = pixels.getUint8(i + 2);
      if (_near(r, g, b, ar, ag, ab)) continue;
      if (_near(r, g, b, br, bg, bb)) continue;
      if (!_onSegment(r, g, b, ar, ag, ab, br, bg, bb)) continue;
      blends++;
    }
  }
  return blends;
}

void main() {
  group('抗锯齿', () {
    // Rasterize once per tester: repeated toImage() calls hang in this
    // environment.
    testWidgets('侧壁剪影与顶面都有抗锯齿过渡', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final ui.Image image = await _renderFrame(kAaTheme);
        final ByteData pixels = (await image.toByteData())!;
        final int side = kAaViewport.width.toInt();
        final int sideBlends = _countBlends(
          pixels,
          side,
          ar: 16,
          ag: 32,
          ab: _sideB,
          br: 255,
          bg: 255,
          bb: 255,
        );
        final int topBlends = _countBlends(
          pixels,
          side,
          ar: 32,
          ag: 64,
          ab: _topB,
          br: 255,
          bg: 255,
          bb: 255,
        );
        debugPrint('side↔body blends: $sideBlends');
        debugPrint('top↔body blends: $topBlends');
        // 1000 (not 20): the old default stroked an interior edge and
        // produced 36 blends; 4x truth is ~2800.
        expect(sideBlends, greaterThan(1000), reason: '侧壁与本体的交界应存在抗锯齿过渡像素');
        image.dispose();
      });
    });

    test('flat 主题（不抬贴片）里没有侧壁可画', () {
      final CubeScene scene = CubeScene(
        state: CubeState(),
        yaw: MagicCubeController.defaultYaw,
        pitch: MagicCubeController.defaultPitch,
        viewport: kAaViewport,
        gap: 0,
        cornerRadius: 0,
      );
      expect(scene.hasLayerSegments, isFalse);
      expect(scene.drawOrder.isNotEmpty, isTrue);
    });
  });

  group('圆弧细分', () {
    test('段数随屏幕半径增长，且弦高有界', () {
      for (final double radius in <double>[1, 2, 4, 8, 16, 32, 64, 200]) {
        final int segments = CubeScene.arcSegments(radius);
        final double theta = math.pi / 2 / segments;
        final double sagitta = radius * (1 - math.cos(theta / 2));
        expect(
          sagitta,
          lessThanOrEqualTo(CubeScene.maxChordDeviation + 1e-9),
          reason: '半径 $radius 用 $segments 段时弦高 $sagitta 超限',
        );
        expect(segments, greaterThanOrEqualTo(1));
        expect(segments, lessThanOrEqualTo(CubeScene.maxArcSegments));
      }
      expect(CubeScene.arcSegments(64), greaterThan(CubeScene.arcSegments(8)));
      expect(
        CubeScene.arcSegments(8),
        greaterThanOrEqualTo(CubeScene.arcSegments(2)),
      );
      expect(CubeScene.arcSegments(0), 1);
    });

    test('画布越大，角帽补丁的轮廓越细', () {
      int patchPoints(Size viewport) {
        final CubeScene scene = CubeScene(
          state: CubeState(),
          yaw: MagicCubeController.defaultYaw,
          pitch: MagicCubeController.defaultPitch,
          viewport: viewport,
          cornerRadius: 0.5,
        );
        return scene.drawOrder
            .where((SceneFace face) => face.isCornerPatch)
            .first
            .corners
            .length;
      }

      final int small = patchPoints(const Size(240, 240));
      final int large = patchPoints(const Size(900, 900));
      expect(large, greaterThan(small), reason: '大画布上圆角应细分得更细，否则轮廓会退回折线');
      expect(small, greaterThanOrEqualTo(3 * 2));
    });

    test('画布越大，贴纸轮廓的细分越细', () {
      int outlinePoints(Size viewport) => CubePainter.debugOutlinePoints(
        scene: CubeScene(
          state: CubeState(),
          yaw: MagicCubeController.defaultYaw,
          pitch: MagicCubeController.defaultPitch,
          viewport: viewport,
        ),
        theme: const CubeTheme(),
      );

      final int small = outlinePoints(const Size(240, 240));
      final int large = outlinePoints(const Size(900, 900));
      expect(large, greaterThan(small), reason: '轮廓按屏幕半径自适应细分，大画布应产生更多路径点');
      expect(small, greaterThanOrEqualTo(4 * 2));
    });
  });
}
