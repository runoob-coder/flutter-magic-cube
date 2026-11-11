import 'dart:math' as math;
import 'dart:typed_data';

import 'vector3.dart';

/// Row-major 3x3 matrix. Cubie orientations contain only -1/0/1; view
/// rotations are arbitrary.
class Mat3 {
  Mat3._(this._m);

  factory Mat3(List<double> values) {
    // Runtime checks, not asserts: release builds would otherwise defer
    // the failure to an unrelated index error.
    if (values.length != 9) {
      throw ArgumentError.value(
        values.length,
        'values',
        'Mat3 requires exactly 9 elements',
      );
    }
    for (final double value in values) {
      if (!value.isFinite) {
        throw ArgumentError.value(
          value,
          'values',
          'Mat3 elements must be finite',
        );
      }
    }
    return ._(.fromList(values));
  }

  final Float64List _m;

  static final Mat3 identity = ._(
    .fromList(<double>[1, 0, 0, 0, 1, 0, 0, 0, 1]),
  );

  double operator [](int index) => _m[index];

  Vec3 transform(Vec3 p) => Vec3(
    _m[0] * p.x + _m[1] * p.y + _m[2] * p.z,
    _m[3] * p.x + _m[4] * p.y + _m[5] * p.z,
    _m[6] * p.x + _m[7] * p.y + _m[8] * p.z,
  );

  Mat3 multiply(Mat3 other) => Mat3(<double>[
    _m[0] * other[0] + _m[1] * other[3] + _m[2] * other[6],
    _m[0] * other[1] + _m[1] * other[4] + _m[2] * other[7],
    _m[0] * other[2] + _m[1] * other[5] + _m[2] * other[8],
    _m[3] * other[0] + _m[4] * other[3] + _m[5] * other[6],
    _m[3] * other[1] + _m[4] * other[4] + _m[5] * other[7],
    _m[3] * other[2] + _m[4] * other[5] + _m[5] * other[8],
    _m[6] * other[0] + _m[7] * other[3] + _m[8] * other[6],
    _m[6] * other[1] + _m[7] * other[4] + _m[8] * other[7],
    _m[6] * other[2] + _m[7] * other[5] + _m[8] * other[8],
  ]);

  /// Only valid for quarter-turn matrices; snapping arbitrary view angles
  /// produces non-orthogonal results.
  Mat3 get snapped =>
      Mat3(<double>[for (final double v in _m) v.roundToDouble()]);

  Mat3 get transpose => Mat3(<double>[
    _m[0],
    _m[3],
    _m[6],
    _m[1],
    _m[4],
    _m[7],
    _m[2],
    _m[5],
    _m[8],
  ]);

  static Mat3 rotationX(double radians) {
    final double c = math.cos(radians);
    final double s = math.sin(radians);
    return Mat3(<double>[1, 0, 0, 0, c, -s, 0, s, c]);
  }

  static Mat3 rotationY(double radians) {
    final double c = math.cos(radians);
    final double s = math.sin(radians);
    return Mat3(<double>[c, 0, s, 0, 1, 0, -s, 0, c]);
  }

  static Mat3 rotationZ(double radians) {
    final double c = math.cos(radians);
    final double s = math.sin(radians);
    return Mat3(<double>[c, -s, 0, s, c, 0, 0, 0, 1]);
  }

  static Mat3 rotation(CubeAxis axis, double radians) => switch (axis) {
    .x => rotationX(radians),
    .y => rotationY(radians),
    .z => rotationZ(radians),
  };

  /// A zero axis means no rotation; the Rodrigues formula would otherwise
  /// degenerate into a scaled identity matrix.
  static Mat3 rotationAround(Vec3 axis, double radians) {
    if (axis.lengthSquared == 0) return identity;
    final Vec3 a = axis.normalized;
    final double c = math.cos(radians);
    final double s = math.sin(radians);
    final double t = 1 - c;
    final double x = a.x;
    final double y = a.y;
    final double z = a.z;
    return Mat3(<double>[
      t * x * x + c,
      t * x * y - s * z,
      t * x * z + s * y,
      t * x * y + s * z,
      t * y * y + c,
      t * y * z - s * x,
      t * x * z - s * y,
      t * y * z + s * x,
      t * z * z + c,
    ]);
  }

  static Mat3 fromViewAngles({required double yaw, required double pitch}) =>
      rotationX(pitch).multiply(rotationY(yaw));

  /// Returns (axis, angle) with a non-negative angle; a zero axis means
  /// no rotation.
  static (Vec3 axis, double angle) axisAngleOf(Mat3 r) {
    final double cosAngle = ((r[0] + r[4] + r[8] - 1) / 2).clamp(-1.0, 1.0);
    final double angle = math.acos(cosAngle);
    final double sin = math.sqrt(math.max(0.0, 1 - cosAngle * cosAngle));
    if (sin < 1e-6) {
      if (cosAngle > 0) return (const .zero(), 0);
      // Near 180 degrees, derive the axis from the diagonal.
      final double ax = math.sqrt(math.max(0.0, (r[0] + 1) / 2));
      final double ay = math.sqrt(math.max(0.0, (r[4] + 1) / 2));
      final double az = math.sqrt(math.max(0.0, (r[8] + 1) / 2));
      // Mirror matrices such as -I have no axis; treat them as no rotation.
      if (ax < 1e-9 && ay < 1e-9 && az < 1e-9) {
        return (const .zero(), 0);
      }
      if (ax >= ay && ax >= az) {
        return (Vec3(ax, _half(r[1], ax), _half(r[2], ax)).normalized, angle);
      }
      if (ay >= az) {
        return (Vec3(_half(r[3], ay), ay, _half(r[5], ay)).normalized, angle);
      }
      return (Vec3(_half(r[6], az), _half(r[7], az), az).normalized, angle);
    }
    return (
      Vec3(r[7] - r[5], r[2] - r[6], r[3] - r[1]) * (1 / (2 * sin)),
      angle,
    );
  }

  static double _half(double value, double component) =>
      component > 1e-9 ? value / (2 * component) : 0;

  /// Built from exact integer trigonometry so repeated turns never drift.
  static final List<Mat3> _quarterTurns = <Mat3>[
    for (final CubeAxis axis in CubeAxis.values)
      for (int quarter = 0; quarter < 4; quarter++)
        _buildQuarterTurn(axis, quarter),
  ];

  static Mat3 quarterTurn(CubeAxis axis, int quarterTurns) {
    final int quarter = ((quarterTurns % 4) + 4) % 4;
    return _quarterTurns[axis.index * 4 + quarter];
  }

  static Mat3 _buildQuarterTurn(CubeAxis axis, int quarter) {
    final double c = <double>[1, 0, -1, 0][quarter];
    final double s = <double>[0, 1, 0, -1][quarter];
    return switch (axis) {
      .x => Mat3(<double>[1, 0, 0, 0, c, -s, 0, s, c]),
      .y => Mat3(<double>[c, 0, s, 0, 1, 0, -s, 0, c]),
      .z => Mat3(<double>[c, -s, 0, s, c, 0, 0, 0, 1]),
    };
  }

  @override
  bool operator ==(Object other) {
    if (other is! Mat3) return false;
    for (int i = 0; i < 9; i++) {
      if (_m[i] != other._m[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    _m[0],
    _m[1],
    _m[2],
    _m[3],
    _m[4],
    _m[5],
    _m[6],
    _m[7],
    _m[8],
  );

  @override
  String toString() =>
      'Mat3([${_m[0]}, ${_m[1]}, ${_m[2]}], '
      '[${_m[3]}, ${_m[4]}, ${_m[5]}], '
      '[${_m[6]}, ${_m[7]}, ${_m[8]}])';
}
