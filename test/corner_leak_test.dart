import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

/// A mid-grey body makes the darker fillet easy to measure; the default
/// near-black body would put the shade difference down in the AA noise.
const ui.Color _testBody = ui.Color(0xFF9A9A9A);

/// Flood-fill the background from the canvas edges. The clipped corners of
/// rounded cubies used to open a see-through star at every junction; the
/// plastic fillet backing must close them without giving up the rounding.
void main() {
  test('圆角缺口被塑料底衬封闭，且内部圆角仍然可见', () async {
    const ui.Size view = ui.Size(300, 300);
    const int cell = 310;
    const int columns = 3;
    const int variants = 3;
    final List<double> yaws = <double>[-0.9, -0.3, 0.5];
    final List<double> pitches = <double>[0.2, 0.9, -0.6];
    final int width = variants * columns * cell;
    final int height = yaws.length * cell;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawPaint(ui.Paint()..color = const ui.Color(0xFF202020));

    for (int variant = 0; variant < variants; variant++) {
      // 0: all square. 1: outer + inner rounded. 2: only outer rounded;
      // comparing 1 and 2 isolates bodyCornerRadius.
      final CubeTheme theme = switch (variant) {
        0 => const CubeTheme(body: _testBody, bodyCornerRadius: 0),
        2 => const CubeTheme(body: _testBody, bodyCornerRadius: 0),
        _ => const CubeTheme(body: _testBody),
      };
      final double radius = variant == 0 ? 0 : theme.outerCornerRadius;
      for (int i = 0; i < yaws.length; i++) {
        for (int j = 0; j < pitches.length; j++) {
          final CubeScene scene = CubeScene(
            state: CubeState(),
            turn: const CubeTurn(axis: CubeAxis.y, layer: 2, angle: -0.7),
            yaw: yaws[i],
            pitch: pitches[j],
            viewport: view,
            gap: theme.gap,
            cornerRadius: radius,
          );
          canvas.save();
          canvas.translate(
            (variant * columns + j) * cell.toDouble(),
            i * cell.toDouble(),
          );
          CubePainter(scene: scene, theme: theme).paint(canvas, view);
          canvas.restore();
        }
      }
    }

    final ui.Image image = await recorder.endRecording().toImage(width, height);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final Uint8List pixels = data!.buffer.asUint8List();

    final List<bool> visited = List<bool>.filled(width * height, false);
    final List<int> stack = <int>[];
    void push(int x, int y) {
      if (x < 0 || y < 0 || x >= width || y >= height) return;
      final int index = y * width + x;
      if (visited[index]) return;
      final int offset = index * 4;
      if (pixels[offset] != 0x20 ||
          pixels[offset + 1] != 0x20 ||
          pixels[offset + 2] != 0x20) {
        return;
      }
      visited[index] = true;
      stack.add(index);
    }

    for (int x = 0; x < width; x++) {
      push(x, 0);
      push(x, height - 1);
    }
    for (int y = 0; y < height; y++) {
      push(0, y);
      push(width - 1, y);
    }
    while (stack.isNotEmpty) {
      final int index = stack.removeLast();
      final int x = index % width;
      final int y = index ~/ width;
      push(x + 1, y);
      push(x - 1, y);
      push(x, y + 1);
      push(x, y - 1);
    }

    int leaksOf(int variant) {
      final int xFrom = variant * columns * cell;
      final int xTo = xFrom + columns * cell;
      int leaks = 0;
      for (int y = 0; y < height; y++) {
        for (int x = xFrom; x < xTo; x++) {
          final int index = y * width + x;
          if (visited[index]) continue;
          final int offset = index * 4;
          if (pixels[offset] == 0x20 &&
              pixels[offset + 1] == 0x20 &&
              pixels[offset + 2] == 0x20) {
            leaks++;
          }
        }
      }
      return leaks;
    }

    /// The fillet is much darker than the flat face. A >20 drop rules out
    /// AA seams from the extra fill, so this collapses to 0 when
    /// bodyCornerRadius silently becomes a no-op (or the backing is drawn
    /// in the face colour).
    int darkerPixels(int a, int b) {
      final int shift = (b - a) * columns * cell;
      int count = 0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < columns * cell; x++) {
          final int roundedPixel = (y * width + x + a * columns * cell) * 4;
          final int squarePixel = roundedPixel + shift * 4;
          if (pixels[squarePixel] - pixels[roundedPixel] > 20 &&
              pixels[squarePixel + 1] - pixels[roundedPixel + 1] > 20 &&
              pixels[squarePixel + 2] - pixels[roundedPixel + 2] > 20) {
            count++;
          }
        }
      }
      return count;
    }

    final int baseline = leaksOf(0);
    final int rounded = leaksOf(1);
    final int outerOnly = leaksOf(2);
    final int filletPixels = darkerPixels(1, 2);
    stdout.writeln(
      '[leak] baseline=$baseline rounded=$rounded '
      'outerOnly=$outerOnly fillet=$filletPixels',
    );

    expect(
      rounded,
      lessThanOrEqualTo(baseline + kMaxExtraLeaks),
      reason:
          '圆角版本漏光 $rounded 明显多于直角基线 $baseline，'
          '说明被裁掉的角没有塑料底衬，背景漏了出来',
    );
    expect(
      outerOnly,
      lessThanOrEqualTo(baseline + kMaxExtraLeaks),
      reason: '只开外角圆角时也不应漏出背景',
    );
    expect(
      filletPixels,
      greaterThan(kMinFilletPixels),
      reason: '圆角版本与内部直角版本几乎一样，说明 bodyCornerRadius 没有生效',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  /// The reported regression was a zoomed-in view: at that pixel scale the
  /// four clipped corners of a junction formed an enclosed white star.
  test('放大特写里圆角结点与全直角一样不漏背景', () async {
    const double side = 420;
    const ui.Size view = ui.Size(side, side);
    const ui.Color background = ui.Color(0xFFF2F4F8);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawPaint(ui.Paint()..color = background);

    for (int variant = 0; variant < 2; variant++) {
      final CubeTheme theme = variant == 0
          ? const CubeTheme(bodyCornerRadius: 0)
          : const CubeTheme();
      final CubeScene scene = CubeScene(
        state: CubeState(),
        yaw: MagicCubeController.defaultYaw,
        pitch: MagicCubeController.defaultPitch,
        viewport: view,
        gap: theme.gap,
        cornerRadius: theme.outerCornerRadius,
        zoom: 1.35,
      );
      canvas.save();
      canvas.translate(variant * side, 0);
      CubePainter(scene: scene, theme: theme).paint(canvas, view);
      canvas.restore();
    }

    final ui.Image image = await recorder.endRecording().toImage(
      (side * 2).toInt(),
      side.toInt(),
    );
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final Uint8List pixels = data!.buffer.asUint8List();
    final int stride = (side * 2).toInt();

    /// Count exact background pixels in the cube's interior. Grazing-angle
    /// gaps appear in both variants and therefore cancel out; the enclosed
    /// white stars only appear when the clipped corners are see-through.
    int backgroundPixels(int variant) {
      final int xFrom = variant * side.toInt();
      int count = 0;
      for (int y = 40; y < side - 40; y++) {
        for (int x = 40; x < side - 40; x++) {
          final int offset = (y * stride + x + xFrom) * 4;
          if (pixels[offset] == 0xF2 &&
              pixels[offset + 1] == 0xF4 &&
              pixels[offset + 2] == 0xF8) {
            count++;
          }
        }
      }
      return count;
    }

    final int square = backgroundPixels(0);
    final int rounded = backgroundPixels(1);
    stdout.writeln('[leak] zoom square=$square rounded=$rounded');
    expect(
      rounded,
      lessThanOrEqualTo(square + 8),
      reason: '放大后圆角结点漏出 $rounded 个背景像素，全直角只有 $square 个',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// The fillet backing closes every clipped corner; only the hairline gaps
/// that already leaked at grazing angles in the all-square baseline remain.
/// AA along the new arc edges accounts for a handful of extra pixels.
const int kMaxExtraLeaks = 12;

/// 9 poses at 300x300 with a mid-grey body: the fillet arcs cover ~3200
/// pixels; an inert bodyCornerRadius (or a backing in the face colour) gives
/// 0. 1000 leaves ample headroom without going back to an AA-only signal.
const int kMinFilletPixels = 1000;
