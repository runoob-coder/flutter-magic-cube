import 'dart:math' as math;

/// Right-handed coordinates: +x right, +y up, +z toward the viewer.
/// Cubie coordinates are integers in -(size-1)/2 ... (size-1)/2.
enum CubeAxis { x, y, z }

const Map<CubeAxis, Vec3> kAxisVectors = <CubeAxis, Vec3>{
  .x: Vec3(1, 0, 0),
  .y: Vec3(0, 1, 0),
  .z: Vec3(0, 0, 1),
};

const List<CubeAxis> _perpendicularX = <CubeAxis>[.y, .z];
const List<CubeAxis> _perpendicularY = <CubeAxis>[.x, .z];
const List<CubeAxis> _perpendicularZ = <CubeAxis>[.x, .y];

/// Returns shared const lists; treat them as read-only.
List<CubeAxis> perpendicularAxes(CubeAxis axis) => switch (axis) {
  .x => _perpendicularX,
  .y => _perpendicularY,
  .z => _perpendicularZ,
};

class Vec3 {
  const Vec3(this.x, this.y, this.z);

  const Vec3.zero() : x = 0, y = 0, z = 0;

  factory Vec3.axis(CubeAxis axis, [double length = 1]) => switch (axis) {
    .x => Vec3(length, 0, 0),
    .y => Vec3(0, length, 0),
    .z => Vec3(0, 0, length),
  };

  final double x;
  final double y;
  final double z;

  double operator [](CubeAxis axis) => switch (axis) {
    .x => x,
    .y => y,
    .z => z,
  };

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);

  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);

  Vec3 operator -() => Vec3(-x, -y, -z);

  Vec3 operator *(double scale) => Vec3(x * scale, y * scale, z * scale);

  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  Vec3 cross(Vec3 other) => Vec3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  double get lengthSquared => x * x + y * y + z * z;

  double get length => math.sqrt(lengthSquared);

  /// The zero vector normalizes to itself.
  Vec3 get normalized {
    final double len = length;
    if (len == 0) return this;
    return Vec3(x / len, y / len, z / len);
  }

  /// Removes floating-point drift; legal cube coordinates and orientations
  /// contain only -1/0/1.
  Vec3 get snapped =>
      Vec3(x.roundToDouble(), y.roundToDouble(), z.roundToDouble());

  CubeAxis get nearestAxis {
    final double ax = x.abs();
    final double ay = y.abs();
    final double az = z.abs();
    if (ax >= ay && ax >= az) return .x;
    if (ay >= az) return .y;
    return .z;
  }

  /// An L1 norm of 1 is insufficient: (0.5, 0.5, 0) is not axis-aligned.
  bool get isAxisAligned {
    const double eps = 1e-6;
    final double ax = x.abs();
    final double ay = y.abs();
    final double az = z.abs();
    if (ax + ay + az < eps) return true;
    return ((ax - 1).abs() < eps && ay < eps && az < eps) ||
        ((ay - 1).abs() < eps && ax < eps && az < eps) ||
        ((az - 1).abs() < eps && ax < eps && ay < eps);
  }

  @override
  bool operator ==(Object other) =>
      other is Vec3 && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vec3(${_f(x)}, ${_f(y)}, ${_f(z)})';

  static String _f(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 3);
}
