import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

import 'antialias_test.dart' show kAaTheme, kAaViewport;

final int _side = kAaViewport.width.toInt();

const List<int> _spot = <int>[183, 61];

Future<ByteData> _render(Size viewport) async {
  final CubeScene scene = CubeScene(
    state: CubeState(),
    yaw: MagicCubeController.defaultYaw,
    pitch: MagicCubeController.defaultPitch,
    viewport: viewport,
    gap: kAaTheme.gap,
    cornerRadius: kAaTheme.outerCornerRadius,
  );
  final CubePainter painter = CubePainter(scene: scene, theme: kAaTheme);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(Offset.zero & viewport, Paint()..color = kAaTheme.body);
  painter.paint(canvas, viewport);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    viewport.width.toInt(),
    viewport.height.toInt(),
  );
  picture.dispose();
  final ByteData data = (await image.toByteData())!;
  image.dispose();
  return data;
}

/// Channels use a 1:2:4 ratio so top/side blends stay collinear while
/// blends with the body deviate, letting each transition be counted.
String _classify(int r, int g, int b) {
  bool near(int cr, int cg, int cb) =>
      (r - cr).abs() <= 6 && (g - cg).abs() <= 6 && (b - cb).abs() <= 6;
  if (near(255, 255, 255)) return '.';
  if (near(32, 64, 128)) return 'T';
  if (near(16, 32, 64)) return 'S';
  final double tt = (r - 32) / (255 - 32);
  if ((g - (64 + tt * (255 - 64))).abs() <= 6 &&
      (b - (128 + tt * (255 - 128))).abs() <= 6 &&
      tt > 0.05 &&
      tt < 0.95) {
    return 't';
  }
  final double ts = (r - 16) / (255 - 16);
  if ((g - (32 + ts * (255 - 32))).abs() <= 6 &&
      (b - (64 + ts * (255 - 64))).abs() <= 6 &&
      ts > 0.05 &&
      ts < 0.95) {
    return 's';
  }
  return '#';
}

String _classifyAt(ByteData d, int x, int y) {
  final int o = (y * _side + x) * 4;
  return _classify(d.getUint8(o), d.getUint8(o + 1), d.getUint8(o + 2));
}

Map<String, int> _histogram(ByteData d) {
  final Map<String, int> counts = <String, int>{};
  for (int y = 0; y < _side; y++) {
    for (int x = 0; x < _side; x++) {
      final String k = _classifyAt(d, x, y);
      counts[k] = (counts[k] ?? 0) + 1;
    }
  }
  return counts;
}

String _format(Map<String, int> counts) {
  int at(String k) => counts[k] ?? 0;
  return "body=${at('.')} top=${at('T')} side=${at('S')} "
      "top-blend=${at('t')} side-blend=${at('s')} other=${at('#')}";
}

String _window(ByteData d, int cx, int cy) {
  final StringBuffer out = StringBuffer();
  for (int y = cy - 9; y <= cy + 9; y++) {
    out.write('|');
    for (int x = cx - 18; x <= cx + 18; x++) {
      out.write(
        x < 0 || y < 0 || x >= _side || y >= _side ? ' ' : _classifyAt(d, x, y),
      );
    }
    out.writeln('|');
  }
  return out.toString();
}

/// 4x supersampling with box downsampling approximates ideal antialiasing
/// and serves as ground truth.
Future<ByteData> _referencePixels() async {
  const int scale = 4;
  final Size viewport = Size(
    kAaViewport.width * scale,
    kAaViewport.height * scale,
  );
  final ByteData raw = await _render(viewport);
  final int big = viewport.width.toInt();
  final Uint8List out = Uint8List(_side * _side * 4);
  for (int y = 0; y < _side; y++) {
    for (int x = 0; x < _side; x++) {
      int r = 0;
      int g = 0;
      int b = 0;
      for (int dy = 0; dy < scale; dy++) {
        for (int dx = 0; dx < scale; dx++) {
          final int i = ((y * scale + dy) * big + x * scale + dx) * 4;
          r += raw.getUint8(i);
          g += raw.getUint8(i + 1);
          b += raw.getUint8(i + 2);
        }
      }
      final int o = (y * _side + x) * 4;
      out[o] = r ~/ 16;
      out[o + 1] = g ~/ 16;
      out[o + 2] = b ~/ 16;
      out[o + 3] = 255;
    }
  }
  return ByteData.view(out.buffer);
}

void main() {
  group('边缘抗锯齿', () {
    testWidgets('过渡像素的分布与 4x 超采样真值一致', (WidgetTester tester) async {
      await tester.runAsync(() async {
        final ByteData truth = await _referencePixels();
        final ByteData actual = await _render(kAaViewport);
        final Map<String, int> expected = _histogram(truth);
        final Map<String, int> measured = _histogram(actual);
        final int sideBlend = measured['s'] ?? 0;
        final int topBlend = measured['t'] ?? 0;
        final int truthSideBlend = expected['s'] ?? 0;
        final int truthTopBlend = expected['t'] ?? 0;

        debugPrint('truth  ${_format(expected)}');
        debugPrint('actual ${_format(measured)}');
        debugPrint('window at (${_spot[0]},${_spot[1]})');
        debugPrint(_window(truth, _spot[0], _spot[1]));
        debugPrint(_window(actual, _spot[0], _spot[1]));

        expect(truthSideBlend, greaterThan(1000));
        expect(truthTopBlend, greaterThan(1000));

        // Stroking top instead of base (or not stroking) yields 36/0
        // blends.
        expect(
          sideBlend,
          greaterThan(truthSideBlend ~/ 2),
          reason: '侧壁↔本体的过渡像素远少于真值：剪影那条边没有描到',
        );

        // Without the top stroke, the top/side seam stays a bright gap.
        expect(
          topBlend,
          lessThan(truthTopBlend * 5 ~/ 4),
          reason: '顶面↔本体的过渡像素远多于真值：顶面与侧壁的交界没被揉匀',
        );
      });
    });
  });
}
