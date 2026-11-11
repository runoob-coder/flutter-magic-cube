import 'cubie.dart';
import 'cube_move.dart';
import 'matrix3.dart';
import 'vector3.dart';

class CubeState {
  CubeState({this.size = 3}) : _cubies = <Cubie>[] {
    validateCubeSize(size);
    id = _nextId++;
    _build();
    _resolveCenterIndices();
    _solvedSnapshot = <Cubie>[for (final Cubie c in _cubies) c.copy()];
    // Expose an unmodifiable view: reset, copy, and center indices rely on
    // a fixed length and stable elements.
    cubies = .unmodifiable(_cubies);
  }

  final int size;

  /// identityHashCode can be reused after GC, which would hit stale cached
  /// geometry; use a monotonically increasing id instead.
  static int _nextId = 0;
  late final int id;

  /// Built in x -> y -> z order, from negative to positive.
  late final List<Cubie> cubies;

  final List<Cubie> _cubies;

  late final List<Cubie> _solvedSnapshot;

  bool? _solved;
  int? _solvedFaceCount;
  List<bool>? _faceSolvedFlags;
  int _revision = 0;

  /// Bumped on every turn/reset so the renderer can reuse static-layer
  /// caches.
  int get revision => _revision;

  void _invalidate() {
    _solved = null;
    _solvedFaceCount = null;
    _faceSolvedFlags = null;
    _revision++;
  }

  int get halfExtent => (size - 1) ~/ 2;

  double coordinateOfLayer(int layer) => (layer - halfExtent).toDouble();

  int layerOfCoordinate(double coordinate) {
    if (!coordinate.isFinite) {
      throw ArgumentError.value(
        coordinate,
        'coordinate',
        'Coordinate must be finite',
      );
    }
    final int layer = coordinate.round() + halfExtent;
    if (layer < 0 || layer >= size) {
      throw RangeError.range(
        layer,
        0,
        size - 1,
        'layer',
        'Coordinate lies outside the cube',
      );
    }
    return layer;
  }

  Cubie? cubieAt(Vec3 position) {
    for (final Cubie cubie in _cubies) {
      if (cubie.position == position) return cubie;
    }
    return null;
  }

  /// Invalid layers throw instead of silently bumping revision and adding
  /// a history step.
  bool applyMove(CubeMove move) {
    if (move.isNoop) return false;
    if (!move.wholeCube && (move.layer < 0 || move.layer >= size)) {
      throw RangeError.range(
        move.layer,
        0,
        size - 1,
        'layer',
        'Layer index out of range',
      );
    }
    _invalidate();
    final Mat3 rotation = .quarterTurn(move.axis, move.quarterTurns);
    final double target = coordinateOfLayer(move.layer);
    for (final Cubie cubie in _cubies) {
      if (!move.wholeCube && cubie.position[move.axis] != target) continue;
      // Quarter-turn matrices are exact integers, so no snapping is needed
      // here.
      cubie.position = rotation.transform(cubie.position);
      cubie.orientation = rotation.multiply(cubie.orientation);
    }
    return true;
  }

  void applyMoves(Iterable<CubeMove> moves) {
    for (final CubeMove move in moves) {
      applyMove(move);
    }
  }

  /// Requires both uniform sticker origins and exactly size^2 stickers per
  /// face; uniformity alone would accept a damaged state as solved.
  bool get isSolved {
    _ensureSolved();
    return _solved!;
  }

  int get solvedFaceCount {
    _ensureSolved();
    return _solvedFaceCount!;
  }

  bool isFaceSolved(Vec3 normal) {
    _ensureSolved();
    final int face = _faceIndexOf(normal);
    return face >= 0 && _faceSolvedFlags![face];
  }

  /// One traversal feeds isSolved, solvedFaceCount, and isFaceSolved.
  void _ensureSolved() {
    if (_solved != null) return;
    final int expected = size * size;
    final List<int?> references = .filled(kFaceCount, null);
    final List<int> counts = .filled(kFaceCount, 0);
    final List<bool> mixed = .filled(kFaceCount, false);
    bool complete = _cubies.length == size * size * size;
    for (final Cubie cubie in _cubies) {
      for (int face = 0; face < kFaceCount; face++) {
        final int? sticker = cubie.stickers[face];
        if (sticker == null) continue;
        final int world = _faceIndexOf(cubie.worldNormalOf(face));
        if (world < 0) {
          complete = false;
          continue;
        }
        counts[world]++;
        final int? reference = references[world];
        if (reference == null) {
          references[world] = sticker;
        } else if (reference != sticker) {
          mixed[world] = true;
        }
      }
    }
    final List<bool> solvedFaces = .generate(
      kFaceCount,
      (int i) => complete && counts[i] == expected && !mixed[i],
    );
    _faceSolvedFlags = solvedFaces;
    _solvedFaceCount = solvedFaces.where((bool value) => value).length;
    _solved = _solvedFaceCount == kFaceCount;
  }

  static int _faceIndexOf(Vec3 n) {
    if (n.x > 0.9999) return kFaceRight;
    if (n.x < -0.9999) return kFaceLeft;
    if (n.y > 0.9999) return kFaceUp;
    if (n.y < -0.9999) return kFaceDown;
    if (n.z > 0.9999) return kFaceFront;
    if (n.z < -0.9999) return kFaceBack;
    return -1;
  }

  void reset() {
    _invalidate();
    for (int i = 0; i < _cubies.length; i++) {
      _cubies[i].copyFrom(_solvedSnapshot[i]);
    }
  }

  /// Keep the revision so callers that compare only revision still update.
  CubeState copy() {
    final CubeState clone = CubeState(size: size);
    for (int i = 0; i < _cubies.length; i++) {
      clone._cubies[i].copyFrom(_cubies[i]);
    }
    // The clone's caches are already empty; invalidating would bump its
    // revision by one.
    clone._revision = _revision;
    return clone;
  }

  /// Indices of the cubies initially at each face center (-1 if absent).
  /// Logos must follow their cubie, not a fixed screen direction.
  late final List<int> centerCubieIndices;

  void _resolveCenterIndices() {
    final List<int> indices = .filled(kFaceCount, -1);
    for (int i = 0; i < _cubies.length; i++) {
      final int face = _centerFaceOf(_cubies[i].position);
      if (face >= 0) indices[face] = i;
    }
    centerCubieIndices = indices;
  }

  int _centerFaceOf(Vec3 p) {
    final double half = halfExtent.toDouble();
    if (p.x == 0 && p.y == 0 && p.z == half) return kFaceFront;
    if (p.x == 0 && p.y == 0 && p.z == -half) return kFaceBack;
    if (p.x == 0 && p.y == half && p.z == 0) return kFaceUp;
    if (p.x == 0 && p.y == -half && p.z == 0) return kFaceDown;
    if (p.x == half && p.y == 0 && p.z == 0) return kFaceRight;
    if (p.x == -half && p.y == 0 && p.z == 0) return kFaceLeft;
    return -1;
  }

  void _build() {
    final int half = halfExtent;
    for (int x = -half; x <= half; x++) {
      for (int y = -half; y <= half; y++) {
        for (int z = -half; z <= half; z++) {
          _cubies.add(
            Cubie(
              position: Vec3(x.toDouble(), y.toDouble(), z.toDouble()),
              stickers: <int?>[
                x == half ? kFaceRight : null,
                x == -half ? kFaceLeft : null,
                y == half ? kFaceUp : null,
                y == -half ? kFaceDown : null,
                z == half ? kFaceFront : null,
                z == -half ? kFaceBack : null,
              ],
            ),
          );
        }
      }
    }
  }
}
