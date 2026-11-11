import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

/// The logo is drawn as an affine cell mesh. Guard both failure modes:
/// cells must not stretch or drop content at seams, and seams must not
/// reveal the white sticker through half-covered antialiased edges.

const List<double> _probeFractions = <double>[
  0.11,
  0.232,
  0.36,
  0.482,
  0.61,
  0.732,
];

const ui.Size _bigView = ui.Size(1200, 1200);

const ui.Size _smallView = ui.Size(300, 300);

const int _cell = 1210;

const double _logoScale = 1;

const int _solidArgb = 0xFF808080;

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

/// Straight edges reveal per-cell distortion: a homography maps lines to
/// lines.
Future<ui.Image> _probeLogo(int side) {
  final Uint8List pixels = Uint8List(side * side * 4);
  final double center = (side - 1) / 2;
  final double radius = side * 0.33;
  const double diamondHalfWidth = 6;
  const int barHalfWidth = 3;
  final List<int> bars = _probeFractions
      .map((double f) => (side * f).round())
      .toList(growable: false);
  for (int y = 0; y < side; y++) {
    for (int x = 0; x < side; x++) {
      final double distance = (x - center).abs() + (y - center).abs();
      bool dark = (distance - radius).abs() <= diamondHalfWidth;
      for (final int bar in bars) {
        if ((x - bar).abs() <= barHalfWidth ||
            (y - bar).abs() <= barHalfWidth) {
          dark = true;
        }
      }
      final int offset = (y * side + x) * 4;
      final int value = dark ? 0 : 255;
      pixels[offset] = value;
      pixels[offset + 1] = value;
      pixels[offset + 2] = value;
      pixels[offset + 3] = 0xFF;
    }
  }
  return _decode(pixels, side, side);
}

Future<ui.Image> _solidLogo(int side) {
  final Uint8List pixels = Uint8List(side * side * 4);
  for (int i = 0; i < side * side; i++) {
    pixels[i * 4] = (_solidArgb >> 16) & 0xFF;
    pixels[i * 4 + 1] = (_solidArgb >> 8) & 0xFF;
    pixels[i * 4 + 2] = _solidArgb & 0xFF;
    pixels[i * 4 + 3] = 0xFF;
  }
  return _decode(pixels, side, side);
}

void main() {
  test('logo 的网格接缝既不丢内容也不露底色', () async {
    final ui.Image probe = await _probeLogo(256);
    final ui.Image solid = await _solidLogo(256);

    CubeScene scene(double yaw, double pitch, ui.Size viewport) => CubeScene(
      state: CubeState(),
      turn: null,
      yaw: yaw,
      pitch: pitch,
      viewport: viewport,
    );
    // Front-on projection is affine, so any remaining distortion comes
    // from the per-cell drawing.
    final CubeScene front = scene(0, 0, _bigView);
    final CubeScene oblique = scene(
      MagicCubeController.defaultYaw,
      MagicCubeController.defaultPitch,
      _smallView,
    );
    const CubeTheme base = CubeTheme(logoScale: _logoScale);
    final CubeTheme probeTheme = base.copyWith(
      centerLogo: probe,
      logoFace: kFaceFront,
    );
    final CubeTheme frontSolidTheme = base.copyWith(
      centerLogo: solid,
      logoFace: kFaceFront,
    );
    final CubeTheme obliqueSolidTheme = base.copyWith(
      centerLogo: solid,
      logoFace: kFaceUp,
    );

    /// Must include sticker lift: the logo is drawn on the raised top face;
    /// at oblique angles omitting it shifts the scan line into the AA edge.
    final double lift = base.stickerThickness.clamp(
      0.0,
      CubeTheme.maxStickerThickness,
    );
    Offset Function(double, double) mapper(CubeScene s, int faceIndex) {
      final int index = s.state.centerCubieIndices[faceIndex];
      final SceneFace face = s.drawOrder.firstWhere(
        (SceneFace f) => f.cubieIndex == index && f.sticker == faceIndex,
        orElse: () => fail('面 $faceIndex 的中心贴纸不可见'),
      );
      final double half = base.stickerScale * _logoScale;
      return (double fx, double fy) {
        final double du = half * (-1 + 2 * fx);
        final double dv = half * (1 - 2 * fy);
        return s.projectViewXYZ(
          face.viewCenter.x +
              face.viewU.x * du +
              face.viewV.x * dv +
              face.viewNormal.x * lift,
          face.viewCenter.y +
              face.viewU.y * du +
              face.viewV.y * dv +
              face.viewNormal.y * lift,
          face.viewCenter.z +
              face.viewU.z * du +
              face.viewV.z * dv +
              face.viewNormal.z * lift,
        );
      };
    }

    final Offset Function(double, double) probeAt = mapper(front, kFaceFront);
    final Offset Function(double, double) obliqueAt = mapper(oblique, kFaceUp);

    // One Picture for all variants: only one toImage() call is safe here.
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawPaint(ui.Paint()..color = const ui.Color(0xFF202020));
    final List<CubeScene> scenes = <CubeScene>[front, front, oblique];
    final List<CubeTheme> themes = <CubeTheme>[
      probeTheme,
      frontSolidTheme,
      obliqueSolidTheme,
    ];
    for (int i = 0; i < scenes.length; i++) {
      canvas.save();
      canvas.translate((i * _cell).toDouble(), 0);
      CubePainter(
        scene: scenes[i],
        theme: themes[i],
      ).paint(canvas, scenes[i].viewport);
      canvas.restore();
    }

    final ui.Image image = await recorder.endRecording().toImage(
      _cell * 3,
      _cell,
    );
    final ByteData? raw = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final Uint8List pixels = raw!.buffer.asUint8List();
    const int width = _cell * 3;

    double lumaAt(int variant, ui.Offset point) {
      final int x = (point.dx + variant * _cell).round();
      final int y = point.dy.round();
      final int offset = (y * width + x) * 4;
      return (pixels[offset] + pixels[offset + 1] + pixels[offset + 2]) /
          (3 * 255);
    }

    final ui.Offset center = probeAt(0.5, 0.5);

    List<List<int>> runs({required bool horizontal}) {
      final double lo = horizontal ? probeAt(0, 0.5).dx : probeAt(0.5, 0).dy;
      final double hi = horizontal ? probeAt(1, 0.5).dx : probeAt(0.5, 1).dy;
      final List<int> darks = <int>[];
      for (int i = (lo - 6).round(); i <= (hi + 6).round(); i++) {
        final double value = horizontal
            ? lumaAt(0, ui.Offset(i.toDouble(), center.dy))
            : lumaAt(0, ui.Offset(center.dx, i.toDouble()));
        if (value < 0.5) darks.add(i);
      }
      final List<List<int>> out = <List<int>>[];
      for (final int value in darks) {
        if (out.isNotEmpty && value - out.last.last <= 1) {
          out.last.add(value);
        } else {
          out.add(<int>[value]);
        }
      }
      return out;
    }

    List<int>? runNear(List<List<int>> all, double target, double tolerance) {
      List<int>? best;
      double bestDistance = tolerance;
      for (final List<int> run in all) {
        final double distance = ((run.first + run.last) / 2 - target).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          best = run;
        }
      }
      return best;
    }

    final List<List<int>> columns = runs(horizontal: true);
    final List<List<int>> rows = runs(horizontal: false);
    final List<double> widths = <double>[];
    final List<double> drifts = <double>[];
    for (final double f in _probeFractions) {
      final List<int>? column = runNear(columns, probeAt(f, 0.5).dx, 3);
      final List<int>? row = runNear(rows, probeAt(0.5, f).dy, 3);
      expect(
        column,
        isNotNull,
        reason:
            'f=$f 的竖线在接缝处丢了'
            '（暗段 ${columns.map((List<int> r) => '${r.first}..${r.last}').join(', ')}）',
      );
      expect(row, isNotNull, reason: 'f=$f 的横线在接缝处丢了');
      widths
        ..add(column!.length.toDouble())
        ..add(row!.length.toDouble());
      drifts
        ..add(((column.first + column.last) / 2 - probeAt(f, 0.5).dx).abs())
        ..add(((row.first + row.last) / 2 - probeAt(0.5, f).dy).abs());
    }

    // Unequal widths are the signature of expanding geometry without the
    // source rect: seam-adjacent bars shrink from 6px to 3px.
    final List<double> sorted = List<double>.from(widths)..sort();
    final double median = sorted[sorted.length ~/ 2];
    for (int i = 0; i < widths.length; i++) {
      final String which =
          '${i.isEven ? '竖' : '横'}线 f=${_probeFractions[i ~/ 2]}';
      expect(
        widths[i],
        greaterThan(median * 0.7),
        reason:
            '$which 只有 ${widths[i]} 像素宽（中位数 $median），'
            '说明接缝把这段内容吃掉了',
      );
      expect(
        widths[i],
        lessThan(median * 1.3),
        reason: '$which 宽 ${widths[i]} 像素，明显超过中位数 $median',
      );
      // Fixed implementation drifts <0.6px; stretching moves bars >1.5px.
      expect(
        drifts[i],
        lessThan(1.5),
        reason:
            '$which 的位置偏了 ${drifts[i].toStringAsFixed(2)} 像素，'
            '说明这一格的内容被拉伸了',
      );
    }

    void expectFlat(
      int variant,
      Offset Function(double, double) at,
      String label,
    ) {
      double minLuma = 1;
      double maxLuma = 0;
      // Scan every pixel: the deficit occupies only 1-2 seam pixels.
      void sample(double fx, double fy) {
        final double value = lumaAt(variant, at(fx, fy));
        if (value < minLuma) minLuma = value;
        if (value > maxLuma) maxLuma = value;
      }

      for (final double fy in <double>[0.28, 0.4, 0.6, 0.72]) {
        for (int x = 0; x < 400; x++) {
          sample(0.12 + 0.76 * x / 399, fy);
        }
      }
      for (final double fx in <double>[0.36, 0.64]) {
        for (int y = 0; y < 400; y++) {
          sample(fx, 0.12 + 0.76 * y / 399);
        }
      }
      expect(
        maxLuma - minLuma,
        lessThan(3 / 255),
        reason:
            '$label：实心 logo 上出现了接缝痕迹，亮度 '
            '${minLuma.toStringAsFixed(4)} ~ ${maxLuma.toStringAsFixed(4)}',
      );
    }

    expectFlat(1, probeAt, '正视');
    expectFlat(2, obliqueAt, '斜视（U 面被压扁、logo 只占几十像素）');

    image.dispose();
    probe.dispose();
    solid.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
