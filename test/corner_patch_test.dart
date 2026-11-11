import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';

/// Every patch vertex must stay inside the projection of the corner
/// cubie's three sticker faces. Regression: mixing rest positions with
/// in-turn orientations made patches shrink and drift outside the corner.
void main() {
  const double gap = 0.055;
  final double half = (1 - gap) / 2;

  for (final double angle in <double>[0.0, -0.35, -0.7, -1.2]) {
    test('拧动 $angle 时补丁仍贴在三个相邻面内', () {
      final CubeState state = CubeState();
      final CubeScene scene = CubeScene(
        state: state,
        turn: CubeTurn(axis: CubeAxis.y, layer: 2, angle: angle),
        yaw: MagicCubeController.defaultYaw,
        pitch: MagicCubeController.defaultPitch,
        viewport: const Size(400, 400),
      );
      final List<SceneFace> patches = scene.drawOrder
          .where((SceneFace face) => face.isCornerPatch)
          .toList();
      // Back-facing corners are culled; 6-8 patches are visible here.
      expect(patches.length, inInclusiveRange(6, 8), reason: '可见外角各有圆角补丁');
      for (final SceneFace patch in patches) {
        final int index = patch.cubieIndex;
        final Vec3 position = scene.cubies[index].position;
        final Mat3 orientation = scene.cubies[index].orientation;
        final List<List<Offset>> quads = <List<Offset>>[
          for (int face = 0; face < kFaceCount; face++)
            if (state.cubies[index].stickers[face] != null)
              _faceQuad(scene, position, orientation, face, half),
        ];
        expect(quads.length, 3, reason: '角块应有三个带贴纸的外表面');
        for (final Offset point in patch.corners) {
          final bool inside = quads.any(
            (List<Offset> quad) => _insideQuad(_inflated(quad), point),
          );
          expect(inside, isTrue, reason: '补丁轮廓点跑到相邻面之外: $point');
        }
      }
    });
  }
}

List<Offset> _faceQuad(
  CubeScene scene,
  Vec3 position,
  Mat3 orientation,
  int faceIndex,
  double half,
) {
  final Vec3 normal = orientation.transform(kFaceNormals[faceIndex]);
  final Vec3 u = orientation.transform(kFaceTangentU[faceIndex]) * half;
  final Vec3 v = orientation.transform(kFaceTangentV[faceIndex]) * half;
  final Vec3 center = position + normal * half;
  return <Offset>[
    scene.project(center - u - v),
    scene.project(center + u - v),
    scene.project(center + u + v),
    scene.project(center - u + v),
  ];
}

/// Allow 2% tolerance: arc endpoints land exactly on face edges.
List<Offset> _inflated(List<Offset> quad) {
  Offset center = Offset.zero;
  for (final Offset point in quad) {
    center += point;
  }
  center /= quad.length.toDouble();
  return <Offset>[
    for (final Offset point in quad) center + (point - center) * 1.02,
  ];
}

bool _insideQuad(List<Offset> polygon, Offset point) {
  bool inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final Offset a = polygon[i];
    final Offset b = polygon[j];
    if ((a.dy > point.dy) != (b.dy > point.dy) &&
        point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
