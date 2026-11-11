import 'dart:math' as math;

import 'vector3.dart';

/// Bounds allocation of size^3 cubies plus a solved snapshot; 11 (1331
/// cubies) is far beyond rendering needs.
const int kMaxCubeSize = 11;

/// Runtime check, not assert: release builds would otherwise construct an
/// illegal cube with a half-offset center layer.
void validateCubeSize(int size) {
  if (size < 3) {
    throw ArgumentError.value(size, 'size', 'Cube size must be at least 3');
  }
  if (size.isEven) {
    throw ArgumentError.value(
      size,
      'size',
      'Only odd cube sizes are supported',
    );
  }
  if (size > kMaxCubeSize) {
    throw ArgumentError.value(
      size,
      'size',
      'Cube size too large; maximum is $kMaxCubeSize',
    );
  }
}

/// A completed turn: axis, layer (0 at the negative end), and quarter-turn
/// count. Positive counts follow the right-hand rule about the positive axis.
class CubeMove {
  const CubeMove({
    required this.axis,
    required this.layer,
    required this.quarterTurns,
    this.wholeCube = false,
  });

  final CubeAxis axis;

  final int layer;

  final int quarterTurns;

  final bool wholeCube;

  /// Normalize first so quarterTurns: 100 does not spin the animation 25
  /// times.
  double get radians => normalizedQuarterTurns * math.pi / 2;

  bool get isNoop => quarterTurns % 4 == 0;

  /// Keep -2 and 2 from both surviving: they are the same half turn, and
  /// equality would otherwise treat R2 and a parsed R2 as different moves.
  int get normalizedQuarterTurns {
    int turns = quarterTurns % 4;
    if (turns > 2) turns -= 4;
    if (turns < -1) turns += 4;
    return turns;
  }

  CubeMove get inverse => CubeMove(
    axis: axis,
    layer: layer,
    quarterTurns: -normalizedQuarterTurns,
    wholeCube: wholeCube,
  );

  /// Higher-order inner layers use a numeric prefix (3X'), which cannot be
  /// confused with 2/' suffixes. Parse with the same size to round-trip.
  String notation({int size = 3}) {
    if (isNoop) return '';
    validateCubeSize(size);
    if (wholeCube) {
      return '${axis.name}${_suffix(_primaryUnits(-1))}';
    }
    final int half = (size - 1) ~/ 2;
    final (String letter, int base) = switch ((axis, layer)) {
      (.x, int l) when l == size - 1 => ('R', -1),
      (.x, 0) => ('L', 1),
      (.x, int l) when l == half => ('M', 1),
      (.y, int l) when l == size - 1 => ('U', -1),
      (.y, 0) => ('D', 1),
      (.y, int l) when l == half => ('E', 1),
      (.z, int l) when l == size - 1 => ('F', -1),
      (.z, 0) => ('B', 1),
      (.z, int l) when l == half => ('S', -1),
      _ => ('', 1),
    };
    if (letter.isNotEmpty) {
      return '$letter${_suffix(_primaryUnits(base))}';
    }
    return '$layer${axis.name.toUpperCase()}${_suffix(_primaryUnits(1))}';
  }

  /// Equality uses normalized semantics; whole-cube turns ignore layer.
  @override
  bool operator ==(Object other) =>
      other is CubeMove &&
      axis == other.axis &&
      (wholeCube || layer == other.layer) &&
      normalizedQuarterTurns == other.normalizedQuarterTurns &&
      wholeCube == other.wholeCube;

  @override
  int get hashCode => Object.hash(
    axis,
    wholeCube ? 0 : layer,
    normalizedQuarterTurns,
    wholeCube,
  );

  @override
  String toString() => notation();

  int _primaryUnits(int base) => ((normalizedQuarterTurns * base) % 4 + 4) % 4;

  static String _suffix(int units) => switch (units) {
    0 => '',
    1 => '',
    2 => '2',
    _ => "'",
  };

  /// Accepts single letters, 2/' suffixes, and numeric layer prefixes.
  /// Invalid suffixes throw FormatException instead of being ignored.
  static final RegExp _tokenPattern = RegExp(
    r"^(\d+)?([UDLRFBMESXYZ])(2['’]?|['’])?$",
    caseSensitive: false,
  );

  /// Use the same size as notation() to round-trip face tokens.
  factory CubeMove.parse(String token, {int size = 3}) {
    validateCubeSize(size);
    final String trimmed = token.trim();
    final RegExpMatch? match = _tokenPattern.firstMatch(trimmed);
    if (match == null) {
      throw FormatException('Invalid cube notation: $token');
    }
    final String? layerToken = match.group(1);
    final String letter = match.group(2)!.toUpperCase();
    final String suffix = match.group(3) ?? '';
    final int units = switch (suffix) {
      '' => 1,
      '2' || "2'" || '2’' => 2,
      "'" || '’' => 3,
      _ => throw FormatException('Invalid cube notation: $token'),
    };
    final (CubeAxis, int, int) info = switch (letter) {
      'R' => (.x, 1, -1),
      'L' => (.x, -1, 1),
      'M' => (.x, 0, 1),
      'U' => (.y, 1, -1),
      'D' => (.y, -1, 1),
      'E' => (.y, 0, 1),
      'F' => (.z, 1, -1),
      'B' => (.z, -1, 1),
      'S' => (.z, 0, -1),
      'X' => (.x, 0, -1),
      'Y' => (.y, 0, -1),
      'Z' => (.z, 0, -1),
      _ => throw FormatException('Invalid cube notation: $token'),
    };
    final bool axisLetter = letter == 'X' || letter == 'Y' || letter == 'Z';
    final int half = (size - 1) ~/ 2;
    late final int layer;
    final int base;
    final bool wholeCube;
    if (layerToken != null) {
      final int? parsed = int.tryParse(layerToken);
      if (parsed == null || parsed < 0 || parsed >= size) {
        throw FormatException(
          'Layer index out of range 0 ... ${size - 1}: $token',
        );
      }
      layer = parsed;
      base = 1;
      wholeCube = false;
    } else {
      // Face tokens encode 3x3 outer-layer coordinates; map them to real
      // layer indices for larger cubes.
      layer = switch (info.$2) {
        -1 => 0,
        1 => size - 1,
        _ => half,
      };
      base = info.$3;
      wholeCube = axisLetter;
    }
    int turns = units * base;
    if (turns > 2) turns -= 4;
    if (turns < -1) turns += 4;
    return CubeMove(
      axis: info.$1,
      layer: layer,
      quarterTurns: turns,
      wholeCube: wholeCube,
    );
  }

  static List<CubeMove> parseSequence(String sequence, {int size = 3}) {
    validateCubeSize(size);
    return sequence
        .trim()
        .split(RegExp(r'\s+'))
        .where((String token) => token.isNotEmpty)
        .map((String token) => CubeMove.parse(token, size: size))
        .toList();
  }

  /// No repeated face; after two turns on one axis, the next must switch.
  static List<CubeMove> randomScramble({
    int length = 20,
    int size = 3,
    math.Random? random,
  }) {
    validateCubeSize(size);
    if (length < 0) {
      throw ArgumentError.value(
        length,
        'length',
        'Scramble length must not be negative',
      );
    }
    final math.Random rnd = random ?? math.Random();
    const List<String> faces = <String>['U', 'D', 'L', 'R', 'F', 'B'];
    const List<String> variants = <String>['', "'", '2'];
    final List<CubeMove> moves = <CubeMove>[];
    String? last;
    String? previous;
    int guard = 0;
    final int guardLimit = length * 200 + 200;
    while (moves.length < length && guard < guardLimit) {
      guard++;
      final String face = faces[rnd.nextInt(faces.length)];
      if (face == last) continue;
      if (last != null &&
          previous != null &&
          _axisOf(face) == _axisOf(previous) &&
          _axisOf(face) == _axisOf(last)) {
        continue;
      }
      final bool positive = face == 'R' || face == 'U' || face == 'F';
      final int units = switch (variants[rnd.nextInt(variants.length)]) {
        "'" => 3,
        '2' => 2,
        _ => 1,
      };
      int turns = units * (positive ? -1 : 1);
      if (turns > 2) turns -= 4;
      if (turns < -1) turns += 4;
      moves.add(
        CubeMove(
          axis: _axisOf(face),
          layer: positive ? size - 1 : 0,
          quarterTurns: turns,
        ),
      );
      previous = last;
      last = face;
    }
    if (moves.length < length) {
      throw StateError(
        'Could not generate a $length-move scramble; check the constraints',
      );
    }
    return moves;
  }

  static CubeAxis _axisOf(String face) => switch (face) {
    'R' || 'L' => .x,
    'U' || 'D' => .y,
    _ => .z,
  };
}

/// An in-progress turn with an arbitrary angle; snapped into a CubeMove
/// only when the gesture or animation settles.
class CubeTurn {
  const CubeTurn({
    required this.axis,
    required this.layer,
    this.angle = 0,
    this.wholeCube = false,
  });

  final CubeAxis axis;

  final int layer;

  final double angle;

  final bool wholeCube;

  CubeTurn withAngle(double newAngle) =>
      CubeTurn(axis: axis, layer: layer, angle: newAngle, wholeCube: wholeCube);

  CubeMove toMove(int quarterTurns) => CubeMove(
    axis: axis,
    layer: layer,
    quarterTurns: quarterTurns,
    wholeCube: wholeCube,
  );

  /// Nearest right angle as an unwrapped quarter count (keeps sign/turns).
  int get nearestQuarterTurns {
    if (!angle.isFinite) return 0;
    return (angle / (math.pi / 2)).round();
  }

  /// Shortest settle target, at most 45 degrees away.
  double get nearestRightAngle => nearestQuarterTurns * math.pi / 2;

  /// Move count modulo 4; for committing state, not for settling.
  int get snappedQuarterTurns {
    final int turns = nearestQuarterTurns % 4;
    return turns > 2 ? turns - 4 : turns;
  }

  @override
  String toString() =>
      'CubeTurn(${axis.name}, layer: $layer, '
      'angle: ${(angle * 180 / math.pi).toStringAsFixed(1)}°)';
}
