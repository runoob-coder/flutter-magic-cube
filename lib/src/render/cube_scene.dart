import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

import '../core/cubie.dart';
import '../core/cube_move.dart';
import '../core/cube_state.dart';
import '../core/matrix3.dart';
import '../core/vector3.dart';

class SceneCubie {
  const SceneCubie({
    required this.index,
    required this.position,
    required this.orientation,
  });

  final int index;

  final Vec3 position;

  final Mat3 orientation;
}

class SceneFace {
  const SceneFace({
    required this.cubieIndex,
    required this.faceIndex,
    required this.sticker,
    required this.worldCenter,
    required this.worldU,
    required this.worldV,
    required this.viewCenter,
    required this.viewU,
    required this.viewV,
    required this.viewNormal,
    required this.corners,
    required this.depth,
    this.exteriorCornerMask = 0,
    this.isCornerPatch = false,
    this.shadeBucket = -1,
  });

  final int cubieIndex;

  final int faceIndex;

  final int? sticker;

  final Vec3 worldCenter;

  final Vec3 worldU;

  final Vec3 worldV;

  final Vec3 viewCenter;

  final Vec3 viewU;

  final Vec3 viewV;

  final Vec3 viewNormal;

  final List<Offset> corners;

  final double depth;

  final int exteriorCornerMask;

  /// Drawn before the cubie's faces so it only shows through the clipped
  /// corner gaps.
  final bool isCornerPatch;

  /// -1 during a turn: non-axis-aligned normals must bypass the shade
  /// cache.
  final int shadeBucket;
}

class SceneHit {
  const SceneHit({
    required this.cubieIndex,
    required this.faceIndex,
    required this.worldNormal,
    required this.worldCenter,
  });

  final int cubieIndex;

  final int faceIndex;

  final Vec3 worldNormal;

  final Vec3 worldCenter;
}

/// One frame of projected geometry shared by painting and hit testing, so
/// what is seen is what is picked.
class CubeScene {
  CubeScene({
    required this.state,
    required this.yaw,
    required this.pitch,
    required this.viewport,
    this.view,
    this.turn,
    double gap = 0.055,
    double cornerRadius = 0.5,
    double zoom = 1,
    double cameraDistance = 9.5,
    double fitRadius = 2.45,
    double stickerScale = 0.84,
  }) : gap = _finite(gap, 0.055).clamp(0.0, 0.9),
       cornerRadius = _finite(cornerRadius, 0.5).clamp(0.0, 1.0),
       zoom = _positive(zoom, 1),
       cameraDistance = _positive(cameraDistance, 9.5),
       fitRadius = _positive(fitRadius, 2.45),
       stickerScale = _finite(stickerScale, 0.84).clamp(0.05, 1.0) {
    _view = view ?? .rotationX(pitch).multiply(.rotationY(yaw));
    final double width = _finite(viewport.width, 320);
    final double height = _finite(viewport.height, 320);
    final double shortSide = math.max(math.min(width, height), 1);
    _focal =
        this.cameraDistance * (shortSide * 0.5) / this.fitRadius * this.zoom;
    _center = Offset(width / 2, height / 2);
    _build();
  }

  static double _finite(double value, double fallback) =>
      value.isFinite ? value : fallback;

  static double _positive(double value, double fallback) =>
      value.isFinite && value > 0 ? value : fallback;

  final CubeState state;

  final double yaw;

  final double pitch;

  /// Passing a matrix directly allows poses flipped past the poles.
  final Mat3? view;

  final Size viewport;

  final CubeTurn? turn;

  final double gap;

  final double cornerRadius;

  final double zoom;

  final double cameraDistance;

  final double fitRadius;

  /// Used only by picking; keep in sync with the painter's sticker scale.
  final double stickerScale;

  final List<SceneCubie> cubies = <SceneCubie>[];

  List<SceneFace> get drawOrder => _drawOrder;
  final List<SceneFace> _drawOrder = <SceneFace>[];

  /// Before/after face lists stay constant during a layer turn and can be
  /// cached as Pictures.
  bool get hasLayerSegments => turn != null && !turn!.wholeCube;

  List<SceneFace> get facesBeforeTurning => _facesBefore;
  List<SceneFace> _facesBefore = <SceneFace>[];

  List<SceneFace> get facesOfTurning => _facesTurning;
  List<SceneFace> _facesTurning = <SceneFace>[];

  List<SceneFace> get facesAfterTurning => _facesAfter;
  List<SceneFace> _facesAfter = <SceneFace>[];

  Object get staticKey => _signature;
  late final _StaticSignature _signature;

  late final Mat3 _view;
  late final double _focal;
  late final Offset _center;

  Offset project(Vec3 p) {
    final Vec3 v = _view.transform(p);
    return projectViewXYZ(v.x, v.y, v.z);
  }

  /// Clamping a behind-camera vertex's depth alone would produce a flipped,
  /// screen-filling triangle; face-level clipping happens in _facesOf.
  Offset projectViewXYZ(double x, double y, double z) {
    final double depth = cameraDistance - z;
    final double safeDepth = depth > minProjectedDepth
        ? depth
        : minProjectedDepth;
    final double scale = _focal / safeDepth;
    return Offset(_center.dx + x * scale, _center.dy - y * scale);
  }

  double depthOf(Vec3 p) {
    final Vec3 v = _view.transform(p);
    return cameraDistance - v.z;
  }

  /// Rescale the hit point into full-face coordinates before containment
  /// testing, so gaps are not mistaken for stickers.
  SceneHit? pick(Offset position) {
    SceneFace? hit;
    for (final SceneFace face in drawOrder) {
      if (face.sticker == null) continue;
      if (_containsSticker(face.corners, position, stickerScale)) hit = face;
    }
    if (hit == null) return null;
    return SceneHit(
      cubieIndex: hit.cubieIndex,
      faceIndex: hit.faceIndex,
      worldNormal: _outwardNormal(hit),
      worldCenter: hit.worldCenter,
    );
  }

  Vec3 _outwardNormal(SceneFace face) {
    final SceneCubie cubie = cubies[face.cubieIndex];
    return cubie.orientation.transform(kFaceNormals[face.faceIndex]).snapped;
  }

  /// Multiple entries are required: cubes sharing a screen would otherwise
  /// evict each other and rebuild every frame.
  static final Map<_StaticSignature, _StaticCache> _staticCache =
      <_StaticSignature, _StaticCache>{};
  static const int _maxStaticCacheEntries = 4;

  /// Max chord deviation r*(1-cos(theta/2)) in logical pixels; 0.12 keeps
  /// faceting sub-pixel without extra vertices.
  static const double maxChordDeviation = 0.12;

  static const int maxArcSegments = 32;

  static const double minProjectedDepth = 0.05;

  static int arcSegments(double radiusPx) {
    if (!(radiusPx > 0)) return 1;
    final double ratio = (maxChordDeviation / radiusPx).clamp(0.0, 0.5);
    final double half = math.acos(1 - ratio);
    if (half <= 0) return maxArcSegments;
    return (math.pi / 4 / half).ceil().clamp(1, maxArcSegments);
  }

  static _StaticCache? _takeStatic(_StaticSignature signature) {
    final _StaticCache? cached = _staticCache.remove(signature);
    if (cached == null) return null;
    _staticCache[signature] = cached;
    return cached;
  }

  static void _putStatic(_StaticCache cache) {
    _staticCache[cache.signature] = cache;
    while (_staticCache.length > _maxStaticCacheEntries) {
      _staticCache.remove(_staticCache.keys.first);
    }
  }

  /// Cache entries retain faces and cubies; call when no cube is mounted.
  static int disposeSceneCache() {
    final int count = _staticCache.length;
    _staticCache.clear();
    return count;
  }

  void _build() {
    final double half = (1 - gap) / 2;
    final bool wholeCubeTurn = turn != null && turn!.wholeCube;
    final Mat3? turnRotation = turn == null
        ? null
        : .rotation(turn!.axis, turn!.angle);
    final double layerCoordinate = turn == null
        ? 0
        : state.coordinateOfLayer(turn!.layer);

    int viewHash = 17;
    for (int i = 0; i < 9; i++) {
      viewHash = viewHash * 31 + _view[i].hashCode;
    }
    _signature = _StaticSignature(
      stateId: state.id,
      revision: state.revision,
      viewKey: viewHash,
      yaw: yaw,
      pitch: pitch,
      width: viewport.width,
      height: viewport.height,
      gap: gap,
      cornerRadius: cornerRadius,
      zoom: zoom,
      cameraDistance: cameraDistance,
      fitRadius: fitRadius,
      turnAxis: turn?.axis,
      turnLayer: turn?.layer ?? -1,
      wholeCube: wholeCubeTurn,
    );
    final _StaticCache? cached = _takeStatic(_signature);
    if (cached != null) {
      _buildTurningLayer(
        cached,
        half: half,
        layerCoordinate: layerCoordinate,
        turnRotation: turnRotation,
        wholeCubeTurn: wholeCubeTurn,
      );
      return;
    }
    _buildEverything(
      half: half,
      layerCoordinate: layerCoordinate,
      turnRotation: turnRotation,
      wholeCubeTurn: wholeCubeTurn,
    );
  }

  void _buildTurningLayer(
    _StaticCache cached, {
    required double half,
    required double layerCoordinate,
    required Mat3? turnRotation,
    required bool wholeCubeTurn,
  }) {
    final List<_PendingCubie> turning = _takeList();
    for (int i = 0; i < state.cubies.length; i++) {
      final Cubie cubie = state.cubies[i];
      final bool inLayer =
          turn == null ||
          wholeCubeTurn ||
          cubie.position[turn!.axis] == layerCoordinate;
      if (!inLayer) {
        cubies.add(cached.cubiePoses[i]!);
        continue;
      }
      Vec3 position = cubie.position;
      Mat3 orientation = cubie.orientation;
      if (turnRotation != null) {
        position = turnRotation.transform(position);
        orientation = turnRotation.multiply(orientation);
      }
      cubies.add(
        SceneCubie(index: i, position: position, orientation: orientation),
      );
      turning.add(
        _takePending()..configure(
          index: i,
          cubie: cubie,
          position: position,
          orientation: orientation,
          depth: depthOf(position),
        ),
      );
    }
    _facesBefore = cached.before;
    _facesAfter = cached.after;
    _facesTurning = <SceneFace>[];
    _collectFaces(turning, half, _facesTurning);
    _drawOrder.addAll(_facesBefore);
    _drawOrder.addAll(_facesTurning);
    _drawOrder.addAll(_facesAfter);
    _releasePending(turning, null);
  }

  void _buildEverything({
    required double half,
    required double layerCoordinate,
    required Mat3? turnRotation,
    required bool wholeCubeTurn,
  }) {
    // A separating plane exists between the turning layer and any resting
    // layer, so their occlusion order is fixed by which side of the plane
    // holds the camera. Sorting by layer therefore avoids clipping artifacts.
    final List<_PendingCubie> turning = _takeList();
    final Map<double, List<_PendingCubie>> resting =
        <double, List<_PendingCubie>>{};
    for (int i = 0; i < state.cubies.length; i++) {
      final Cubie cubie = state.cubies[i];
      final bool inLayer =
          turn == null ||
          turn!.wholeCube ||
          cubie.position[turn!.axis] == layerCoordinate;
      Vec3 position = cubie.position;
      Mat3 orientation = cubie.orientation;
      if (inLayer && turnRotation != null) {
        position = turnRotation.transform(position);
        orientation = turnRotation.multiply(orientation);
      }
      cubies.add(
        SceneCubie(index: i, position: position, orientation: orientation),
      );
      final _PendingCubie item = _takePending()
        ..configure(
          index: i,
          cubie: cubie,
          position: position,
          orientation: orientation,
          depth: depthOf(position),
        );
      if (turn == null || inLayer) {
        turning.add(item);
      } else {
        resting.putIfAbsent(cubie.position[turn!.axis], _takeList).add(item);
      }
    }

    final List<_RenderGroup> groups = <_RenderGroup>[];
    if (turn == null || wholeCubeTurn) {
      groups.add(_RenderGroup(coordinate: 0, items: turning, isTurning: true));
    } else {
      // The view rotation is orthogonal, so the camera's world position is
      // the third row of the transposed view matrix times the distance.
      final Vec3 camera = Vec3(_view[6], _view[7], _view[8]) * cameraDistance;
      final double cameraCoordinate = camera[turn!.axis];
      final List<_RenderGroup> ordered = <_RenderGroup>[
        _RenderGroup(
          coordinate: layerCoordinate,
          items: turning,
          isTurning: true,
        ),
        for (final MapEntry<double, List<_PendingCubie>> entry
            in resting.entries)
          _RenderGroup(coordinate: entry.key, items: entry.value),
      ];
      // Break ties by camera side and coordinate for deterministic ordering.
      ordered.sort((_RenderGroup a, _RenderGroup b) {
        final double da = a.coordinate - cameraCoordinate;
        final double db = b.coordinate - cameraCoordinate;
        final int byDistance = db.abs().compareTo(da.abs());
        if (byDistance != 0) return byDistance;
        final int bySide = (db >= 0 ? 1 : -1).compareTo(da >= 0 ? 1 : -1);
        if (bySide != 0) return bySide;
        return a.coordinate.compareTo(b.coordinate);
      });
      groups.addAll(ordered);
    }

    bool seenTurning = false;
    for (final _RenderGroup group in groups) {
      final List<SceneFace> target = group.isTurning
          ? _facesTurning
          : (seenTurning ? _facesAfter : _facesBefore);
      _collectFaces(group.items, half, target);
      if (group.isTurning) seenTurning = true;
    }
    _drawOrder.addAll(_facesBefore);
    _drawOrder.addAll(_facesTurning);
    _drawOrder.addAll(_facesAfter);
    _cacheStaticParts(layerCoordinate, wholeCubeTurn);

    // Pooled temporaries are internal to CubeScene and safe to reuse across
    // frames.
    _releasePending(turning, resting);
  }

  void _cacheStaticParts(double layerCoordinate, bool wholeCubeTurn) {
    if (turn == null || wholeCubeTurn) {
      return;
    }
    final List<SceneCubie?> poses = .filled(cubies.length, null);
    for (int i = 0; i < cubies.length; i++) {
      if (state.cubies[i].position[turn!.axis] == layerCoordinate) continue;
      poses[i] = cubies[i];
    }
    _putStatic(_StaticCache(_signature, poses, _facesBefore, _facesAfter));
  }

  void _collectFaces(
    List<_PendingCubie> items,
    double half,
    List<SceneFace> out,
  ) {
    items.sort(
      (_PendingCubie a, _PendingCubie b) => b.depth.compareTo(a.depth),
    );
    for (final _PendingCubie item in items) {
      if (!item.cubie.hasSticker && _isHidden(item.cubie)) continue;
      final List<SceneFace> faces = _facesOf(item, half);
      faces.sort((SceneFace a, SceneFace b) => b.depth.compareTo(a.depth));
      // Draw the patch first: the faces clip it into the corner gap. Drawing
      // it last would cover the corner and leak outside the silhouette.
      final SceneFace? patch = _cornerPatch(item, half);
      if (patch != null) out.add(patch);
      out.addAll(faces);
    }
  }

  void _releasePending(
    List<_PendingCubie> turning,
    Map<double, List<_PendingCubie>>? resting,
  ) {
    _pendingPool.addAll(_borrowed);
    _borrowed.clear();
    _listPool.add(turning);
    if (resting == null) return;
    for (final List<_PendingCubie> list in resting.values) {
      _listPool.add(list);
    }
  }

  static final List<_PendingCubie> _pendingPool = <_PendingCubie>[];

  static final List<List<_PendingCubie>> _listPool = <List<_PendingCubie>>[];

  final List<_PendingCubie> _borrowed = <_PendingCubie>[];

  _PendingCubie _takePending() {
    final _PendingCubie item = _pendingPool.isNotEmpty
        ? _pendingPool.removeLast()
        : _PendingCubie();
    _borrowed.add(item);
    return item;
  }

  List<_PendingCubie> _takeList() => _listPool.isNotEmpty
      ? (_listPool.removeLast()..clear())
      : <_PendingCubie>[];

  bool _isHidden(Cubie cubie) {
    final int half = state.halfExtent;
    return cubie.position.x.abs() != half &&
        cubie.position.y.abs() != half &&
        cubie.position.z.abs() != half;
  }

  List<SceneFace> _facesOf(_PendingCubie item, double half) {
    final List<SceneFace> faces = <SceneFace>[];
    final int extent = state.halfExtent;
    final Vec3 rest = item.cubie.position;
    for (int faceIndex = 0; faceIndex < kFaceCount; faceIndex++) {
      final Vec3 normal = item.orientation.transform(kFaceNormals[faceIndex]);
      final Vec3 center = item.position + normal * half;
      final Vec3 viewCenter = _view.transform(center);
      final Vec3 viewNormal = _view.transform(normal);
      final bool frontFacing =
          viewNormal.x * -viewCenter.x +
              viewNormal.y * -viewCenter.y +
              viewNormal.z * (cameraDistance - viewCenter.z) >
          0;
      if (!frontFacing) continue;

      final Vec3 unitU = item.orientation.transform(kFaceTangentU[faceIndex]);
      final Vec3 unitV = item.orientation.transform(kFaceTangentV[faceIndex]);
      final Vec3 u = unitU * half;
      final Vec3 v = unitV * half;
      final Vec3 viewU = _view.transform(u);
      final Vec3 viewV = _view.transform(v);
      // Skip the whole face if its nearest corner is behind the near plane.
      final double nearestDepth =
          cameraDistance - (viewCenter.z + viewU.z.abs() + viewV.z.abs());
      if (nearestDepth <= minProjectedDepth) continue;
      final List<Offset> corners = <Offset>[
        _project(viewCenter, viewU, viewV, -1, -1),
        _project(viewCenter, viewU, viewV, 1, -1),
        _project(viewCenter, viewU, viewV, 1, 1),
        _project(viewCenter, viewU, viewV, -1, 1),
      ];
      faces.add(
        SceneFace(
          cubieIndex: item.index,
          faceIndex: faceIndex,
          sticker: item.cubie.stickers[faceIndex],
          worldCenter: center,
          worldU: u,
          worldV: v,
          viewCenter: viewCenter,
          viewU: viewU,
          viewV: viewV,
          viewNormal: viewNormal,
          corners: corners,
          depth: cameraDistance - viewCenter.z,
          exteriorCornerMask: _exteriorCornerMask(
            rest,
            extent,
            item.cubie.orientation,
            faceIndex,
          ),
          shadeBucket: _bucketOf(normal),
        ),
      );
    }
    return faces;
  }

  /// Use the rest pose: corner rounding belongs to the plastic part and
  /// must follow its cubie during a turn.
  static int _exteriorCornerMask(
    Vec3 rest,
    int extent,
    Mat3 restOrientation,
    int faceIndex,
  ) {
    final Vec3 normal = restOrientation.transform(kFaceNormals[faceIndex]);
    final Vec3 unitU = restOrientation.transform(kFaceTangentU[faceIndex]);
    final Vec3 unitV = restOrientation.transform(kFaceTangentV[faceIndex]);
    int mask = 0;
    for (int corner = 0; corner < 4; corner++) {
      final double su = (corner == 1 || corner == 2) ? 1 : -1;
      final double sv = corner >= 2 ? 1 : -1;
      if (rest.x != (normal.x + unitU.x * su + unitV.x * sv) * extent) continue;
      if (rest.y != (normal.y + unitU.y * su + unitV.y * sv) * extent) continue;
      if (rest.z != (normal.z + unitU.z * su + unitV.z * sv) * extent) continue;
      mask |= 1 << corner;
    }
    return mask;
  }

  /// Fills the gap left by three rounded adjacent faces; shading uses the
  /// average of visible adjacent normals to avoid dark contour seams.
  SceneFace? _cornerPatch(_PendingCubie item, double half) {
    final int extent = state.halfExtent;
    final Vec3 rest = item.cubie.position;
    if (rest.x.abs() != extent ||
        rest.y.abs() != extent ||
        rest.z.abs() != extent) {
      return null;
    }
    final double radius = cornerRadius.clamp(0.0, 1.0) * half;
    if (radius <= 0) return null;

    // Resolve the outward corner in the rest pose (transpose maps it back
    // to the local frame), then transform with the current orientation so
    // the patch stays attached while the layer turns.
    final Vec3 target = Vec3(_sign(rest.x), _sign(rest.y), _sign(rest.z));
    final Vec3 local = item.cubie.orientation.transpose
        .transform(target)
        .snapped;
    final Vec3 d1 =
        item.orientation.transform(const Vec3(1, 0, 0)) * _sign(local.x);
    final Vec3 d2 =
        item.orientation.transform(const Vec3(0, 1, 0)) * _sign(local.y);
    final Vec3 d3 =
        item.orientation.transform(const Vec3(0, 0, 1)) * _sign(local.z);
    final Vec3 outward = d1 + d2 + d3;

    // One visible adjacent face is enough; the corner diagonal alone would
    // misclassify patches near the silhouette.
    Vec3 shade = const .zero();
    int visible = 0;
    for (final Vec3 d in <Vec3>[d1, d2, d3]) {
      final Vec3 viewNormal = _view.transform(d);
      final Vec3 center = item.position + d * half;
      // Transform the face center into view space too; mixing frames makes
      // visible corners disappear at oblique angles.
      final Vec3 viewCenter = _view.transform(center);
      if (viewNormal.x * -viewCenter.x +
              viewNormal.y * -viewCenter.y +
              viewNormal.z * (cameraDistance - viewCenter.z) <=
          0) {
        continue;
      }
      shade += viewNormal;
      visible++;
    }
    if (visible == 0) return null;

    final Vec3 cornerNormal = outward.normalized;
    final Vec3 viewNormal = (shade * (1 / visible)).normalized;
    final Vec3 sample =
        item.position + outward * (half - radius) + cornerNormal * radius;
    final Vec3 viewSample = _view.transform(sample);

    final double patchDepth = cameraDistance - viewSample.z;
    if (patchDepth <= minProjectedDepth) return null;
    final int segments = arcSegments(radius * _focal / patchDepth);
    final List<Offset> points = <Offset>[];
    final double inset = half - radius;
    void addArc(Vec3 pivot, Vec3 from, Vec3 to, {bool reverse = false}) {
      final Vec3 pivotView = _view.transform(pivot);
      final Vec3 fromView = _view.transform(from * radius);
      final Vec3 toView = _view.transform(to * radius);
      for (int step = 0; step <= segments; step++) {
        final double progress = switch (reverse) {
          true => (segments - step) / segments,
          false => step / segments,
        };
        final double angle = progress * math.pi / 2;
        final double c = math.cos(angle);
        final double s = math.sin(angle);
        points.add(
          projectViewXYZ(
            pivotView.x + fromView.x * c + toView.x * s,
            pivotView.y + fromView.y * c + toView.y * s,
            pivotView.z + fromView.z * c + toView.z * s,
          ),
        );
      }
    }

    addArc(item.position + d1 * half + (d2 + d3) * inset, d2, d3);
    addArc(item.position + d3 * half + (d1 + d2) * inset, d1, d2);
    addArc(
      item.position + d2 * half + (d1 + d3) * inset,
      d1,
      d3,
      reverse: true,
    );

    return SceneFace(
      cubieIndex: item.index,
      faceIndex: 0,
      sticker: null,
      worldCenter: sample,
      worldU: const .zero(),
      worldV: const .zero(),
      viewCenter: viewSample,
      viewU: const .zero(),
      viewV: const .zero(),
      viewNormal: viewNormal,
      corners: points,
      depth: cameraDistance - viewSample.z,
      isCornerPatch: true,
    );
  }

  static double _sign(double value) => value < 0 ? -1 : 1;

  /// 0.9999 separates exact +/-1 normals from 45-degree turns (~0.707).
  static int _bucketOf(Vec3 normal) {
    if (normal.x > 0.9999) return kFaceRight;
    if (normal.x < -0.9999) return kFaceLeft;
    if (normal.y > 0.9999) return kFaceUp;
    if (normal.y < -0.9999) return kFaceDown;
    if (normal.z > 0.9999) return kFaceFront;
    if (normal.z < -0.9999) return kFaceBack;
    return -1;
  }

  Offset _project(Vec3 center, Vec3 u, Vec3 v, double du, double dv) {
    final double x = center.x + u.x * du + v.x * dv;
    final double y = center.y + u.y * du + v.y * dv;
    final double z = center.z + u.z * du + v.z * dv;
    final double depth = cameraDistance - z;
    final double safeDepth = depth > minProjectedDepth
        ? depth
        : minProjectedDepth;
    final double scale = _focal / safeDepth;
    return Offset(_center.dx + x * scale, _center.dy - y * scale);
  }

  static bool _containsSticker(
    List<Offset> corners,
    Offset point,
    double scale,
  ) {
    if (scale >= 1) return _containsPoint(corners, point);
    if (scale <= 0 || corners.length < 4) return false;
    final double cx =
        (corners[0].dx + corners[1].dx + corners[2].dx + corners[3].dx) / 4;
    final double cy =
        (corners[0].dy + corners[1].dy + corners[2].dy + corners[3].dy) / 4;
    return _containsPoint(
      corners,
      Offset(cx + (point.dx - cx) / scale, cy + (point.dy - cy) / scale),
    );
  }

  static bool _containsPoint(List<Offset> polygon, Offset point) {
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
}

class _RenderGroup {
  _RenderGroup({
    required this.coordinate,
    required this.items,
    this.isTurning = false,
  });

  final double coordinate;

  final List<_PendingCubie> items;

  final bool isTurning;
}

/// Turn angle is deliberately excluded: it affects only the turning layer.
@immutable
class _StaticSignature {
  const _StaticSignature({
    required this.stateId,
    required this.revision,
    required this.viewKey,
    required this.yaw,
    required this.pitch,
    required this.width,
    required this.height,
    required this.gap,
    required this.cornerRadius,
    required this.zoom,
    required this.cameraDistance,
    required this.fitRadius,
    required this.turnAxis,
    required this.turnLayer,
    required this.wholeCube,
  });

  final int stateId;
  final int revision;

  final int viewKey;
  final double yaw;
  final double pitch;
  final double width;
  final double height;
  final double gap;
  final double cornerRadius;
  final double zoom;
  final double cameraDistance;
  final double fitRadius;
  final CubeAxis? turnAxis;
  final int turnLayer;
  final bool wholeCube;

  @override
  bool operator ==(Object other) =>
      other is _StaticSignature &&
      stateId == other.stateId &&
      revision == other.revision &&
      viewKey == other.viewKey &&
      yaw == other.yaw &&
      pitch == other.pitch &&
      width == other.width &&
      height == other.height &&
      gap == other.gap &&
      cornerRadius == other.cornerRadius &&
      zoom == other.zoom &&
      cameraDistance == other.cameraDistance &&
      fitRadius == other.fitRadius &&
      turnAxis == other.turnAxis &&
      turnLayer == other.turnLayer &&
      wholeCube == other.wholeCube;

  @override
  int get hashCode => Object.hash(
    stateId,
    revision,
    viewKey,
    yaw,
    pitch,
    width,
    height,
    gap,
    cornerRadius,
    zoom,
    cameraDistance,
    fitRadius,
    turnAxis,
    turnLayer,
    wholeCube,
  );
}

class _StaticCache {
  const _StaticCache(this.signature, this.cubiePoses, this.before, this.after);

  final _StaticSignature signature;

  final List<SceneCubie?> cubiePoses;

  final List<SceneFace> before;

  final List<SceneFace> after;
}

/// Mutable and pooled; used only inside _build.
class _PendingCubie {
  _PendingCubie();

  int index = 0;
  late Cubie cubie;
  Vec3 position = .zero();
  Mat3 orientation = .identity;
  double depth = 0;

  void configure({
    required int index,
    required Cubie cubie,
    required Vec3 position,
    required Mat3 orientation,
    required double depth,
  }) {
    this.index = index;
    this.cubie = cubie;
    this.position = position;
    this.orientation = orientation;
    this.depth = depth;
  }
}
