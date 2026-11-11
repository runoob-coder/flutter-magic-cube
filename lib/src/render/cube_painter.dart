import 'dart:math' as math;
import 'dart:ui' show Image, Picture, PictureRecorder, Vertices;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../theme/cube_theme.dart';
import '../core/vector3.dart';
import 'cube_scene.dart';

/// Painter's algorithm over depth-sorted faces; outlines are generated in
/// normalized face coordinates, then projected point by point.
class CubePainter extends CustomPainter {
  CubePainter({required this.scene, required this.theme, super.repaint});

  CubeScene scene;

  CubeTheme theme;

  /// Reusing this painter instance requires a repaint Listenable:
  /// RenderCustomPaint skips shouldRepaint when the same instance is set.
  void update({CubeScene? scene, CubeTheme? theme}) {
    if (scene != null) this.scene = scene;
    if (theme != null) this.theme = theme;
  }

  /// View-space light; fixed so highlights stay stable while the cube turns.
  static const Vec3 lightDirection = Vec3(-0.32, 0.46, 0.83);

  /// Static because painters are rebuilt every frame; outlines depend only
  /// on theme radii.
  static final Map<_OutlineKey, _Outline> _outlineCache =
      <_OutlineKey, _Outline>{};

  static final Map<_ShadeKey, Color> _shadeCache = <_ShadeKey, Color>{};

  /// Static across painter instances; entries own Pictures and must be
  /// disposed on eviction. Keep several for cubes sharing a frame.
  static final Map<_LayerKey, _LayerPictures> _layerCache =
      <_LayerKey, _LayerPictures>{};
  static const int _maxLayerCacheEntries = 4;

  /// Bounded because keys include continuous brightness and pixel scale.
  static const int _maxShadeCacheEntries = 512;
  static const int _maxOutlineCacheEntries = 64;

  /// Call when the last cube unmounts: Pictures hold native resources and
  /// theme-keyed shade/outline entries otherwise never expire.
  static void disposeCaches() {
    for (final _LayerPictures pictures in _layerCache.values) {
      pictures.dispose();
    }
    _layerCache.clear();
    _shadeCache.clear();
    _outlineCache.clear();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final _PaintScope scope = _PaintScope(theme, _pixelScale());
    if (!scene.hasLayerSegments) {
      _paintFaces(canvas, scene.drawOrder, scope);
      return;
    }
    final _LayerKey key = _LayerKey(scene.staticKey, theme);
    _LayerPictures? pictures = _layerCache[key];
    if (pictures == null) {
      pictures = _recordLayers(key, scope);
      if (_layerCache.length >= _maxLayerCacheEntries) {
        _layerCache.remove(_layerCache.keys.first)?.dispose();
      }
      _layerCache[key] = pictures;
    } else {
      // Refresh LRU order on a hit, or 3+ cubes would evict a live entry.
      _layerCache.remove(key);
      _layerCache[key] = pictures;
    }
    canvas.drawPicture(pictures.before);
    _paintFaces(canvas, scene.facesOfTurning, scope);
    canvas.drawPicture(pictures.after);
  }

  _LayerPictures _recordLayers(_LayerKey key, _PaintScope scope) {
    final PictureRecorder beforeRecorder = PictureRecorder();
    _paintFaces(Canvas(beforeRecorder), scene.facesBeforeTurning, scope);
    final Picture before = beforeRecorder.endRecording();
    final PictureRecorder afterRecorder = PictureRecorder();
    _paintFaces(Canvas(afterRecorder), scene.facesAfterTurning, scope);
    final Picture after = afterRecorder.endRecording();
    return _LayerPictures(key, before, after);
  }

  void _paintFaces(Canvas canvas, List<SceneFace> faces, _PaintScope scope) {
    final CubeTheme theme = scope.theme;
    for (final SceneFace face in faces) {
      _drawBody(
        canvas,
        face,
        scope,
        _shadedFor(
          face,
          theme.body,
          _intensity(
            face.viewNormal,
            theme.ambient,
            theme.diffuse,
            theme.lighting,
          ),
          _kindBody,
          _slotBody,
        ),
      );

      final int? sticker = face.sticker;
      if (sticker == null) continue;
      _drawTile(
        canvas,
        face,
        scope,
        scope.shadowPaint,
        scope.stickerColors[sticker],
        _intensity(
          face.viewNormal,
          theme.stickerAmbient,
          theme.stickerDiffuse,
          theme.lighting,
        ),
        sticker,
      );
    }
  }

  double _pixelScale() {
    final Offset origin = scene.projectViewXYZ(0, 0, 0);
    final Offset unit = scene.projectViewXYZ(1, 0, 0);
    return (unit - origin).distance;
  }

  @override
  bool shouldRepaint(covariant CubePainter oldDelegate) =>
      // Compare content: widgets rebuild scene/painter each frame, so an
      // identity check would repaint even when nothing changed.
      oldDelegate.scene.staticKey != scene.staticKey ||
      oldDelegate.scene.turn?.angle != scene.turn?.angle ||
      oldDelegate.theme != theme;

  @visibleForTesting
  static int debugOutlinePoints({
    required CubeScene scene,
    required CubeTheme theme,
  }) {
    final CubePainter painter = CubePainter(scene: scene, theme: theme);
    return painter
        ._outlineFor(-1, _PaintScope(theme, painter._pixelScale()))
        .points
        .length;
  }

  /// CubeTheme is const-constructed, so validate at the render boundary:
  /// 0/negative/NaN would collapse the sticker or produce NaN paths.
  double get _stickerScale =>
      theme.stickerScale.isFinite ? theme.stickerScale.clamp(0.05, 1.0) : 0.84;

  static double _intensity(
    Vec3 viewNormal,
    double ambient,
    double diffuse,
    bool lighting,
  ) {
    if (!lighting) return 1.0;
    final double lambert =
        viewNormal.x * lightDirection.x +
        viewNormal.y * lightDirection.y +
        viewNormal.z * lightDirection.z;
    return ambient + diffuse * math.max(0.0, lambert);
  }

  /// A rounded plastic corner catches less light than the flat face; the
  /// fillet backing is darkened by this factor so the arc stays legible.
  static const double _cornerFilletShade = 0.65;

  static const int _slotBody = 6;

  static const int _kindBody = 0;
  static const int _kindSticker = 1;
  static const int _kindSide = 2;

  Color _shadedFor(
    SceneFace face,
    Color color,
    double intensity,
    int kind,
    int slot,
  ) {
    final int bucket = face.shadeBucket;
    if (bucket < 0) {
      return _finishShade(color, intensity, kind);
    }
    // Light is view-space, so the same world normal has different
    // brightness per view angle; the key must include quantized intensity.
    final _ShadeKey key = _ShadeKey(
      theme,
      bucket,
      slot,
      kind,
      _intensityBucket(intensity),
    );
    final Color? cached = _shadeCache[key];
    if (cached != null) return cached;
    final Color value = _finishShade(color, intensity, kind);
    if (_shadeCache.length >= _maxShadeCacheEntries) {
      _shadeCache.remove(_shadeCache.keys.first);
    }
    _shadeCache[key] = value;
    return value;
  }

  /// Quantize to 1/256; NaN maps to a stable bucket to keep Map keys valid.
  static int _intensityBucket(double intensity) =>
      intensity.isFinite ? (intensity * 256).round().clamp(0, 2048) : 256;

  Color _finishShade(Color color, double intensity, int kind) {
    final Color shaded = _shade(color, intensity);
    return kind == _kindSide
        ? _scale(shaded, theme.stickerSideShade.clamp(0.0, 1.0))
        : shaded;
  }

  static Color _shade(Color color, double intensity) {
    if (!intensity.isFinite) return color;
    if (intensity >= 1) {
      final double t = ((intensity - 1) * 0.85).clamp(0.0, 1.0);
      return .lerp(color, const Color(0xFFFFFFFF), t)!;
    }
    return _scale(color, intensity.clamp(0.0, 1.0));
  }

  static Color _scale(Color color, double factor) {
    if (!factor.isFinite) return color;
    return .from(
      alpha: color.a,
      red: color.r * factor,
      green: color.g * factor,
      blue: color.b * factor,
    );
  }

  /// Two corner radii: outerCornerRadius for the cube's 8 exterior corners,
  /// bodyCornerRadius for all others. Clamp by scene.cornerRadius so patches
  /// always cover the gap.
  void _drawBody(
    Canvas canvas,
    SceneFace face,
    _PaintScope scope,
    Color color,
  ) {
    final Paint fill = scope.fill;
    fill.color = color;
    final double outer = math
        .min(theme.outerCornerRadius, scene.cornerRadius)
        .clamp(0.0, 1.0);
    final double inner = theme.bodyCornerRadius.clamp(0.0, 1.0);
    final int mask = face.exteriorCornerMask;
    final bool roundsExterior = mask != 0 && outer > 0;
    final bool roundsInner = inner > 0;
    if (face.isCornerPatch || (!roundsExterior && !roundsInner)) {
      canvas.drawPath(_pathOf(face.corners), fill);
      return;
    }
    if (roundsInner) {
      // Rounding clips a quarter-disc out of every face corner. That recess
      // used to be see-through: four clipped corners meet at each junction
      // and expose the page background as a white star. Back the face with
      // the same quad using square inner corners, shaded like the plastic
      // fillet that rounds a real cubie corner; the rounded pass below then
      // trims the fillet down to the arc, so bodyCornerRadius stays visible
      // and nothing can leak through. Exterior corners stay rounded in the
      // backing too, so the cube silhouette is unchanged.
      fill.color = _scale(color, _cornerFilletShade);
      canvas.drawPath(
        _outlinePath(
          face,
          _outlineFor(_bodyKey(mask, false), scope).points,
          1,
          0,
        ),
        fill,
      );
      fill.color = color;
    }
    canvas.drawPath(
      _outlinePath(
        face,
        _outlineFor(_bodyKey(mask, roundsInner), scope).points,
        1,
        0,
      ),
      fill,
    );
  }

  /// Low bit: round inner corners; high bits: exterior corner mask.
  static int _bodyKey(int mask, bool roundInner) =>
      (mask << 1) | (roundInner ? 1 : 0);

  void _drawTile(
    Canvas canvas,
    SceneFace face,
    _PaintScope scope,
    Paint? shadowPaint,
    Color color,
    double intensity,

    /// Sticker origin face index, used as the shade-cache slot.
    int slot,
  ) {
    final Paint fill = scope.fill;
    final _Outline outline = _outlineFor(-1, scope);
    final int count = outline.points.length;
    final double scale = _stickerScale;
    final double thickness = theme.stickerThickness.clamp(
      0.0,
      CubeTheme.maxStickerThickness,
    );
    final double shadowOffset = theme.stickerShadowOffset.clamp(
      0.0,
      CubeTheme.maxStickerShadowOffset,
    );
    final bool raised = thickness > 0;

    // Buffers are shared across all stickers in a frame: paint() records
    // serially and Vertices/Path copy the point data at construction.
    final List<Offset> base = scope.baseBuffer(count);
    final List<Offset> top = raised ? scope.topBuffer(count) : base;
    for (int i = 0; i < count; i++) {
      final Offset local = outline.points[i];
      final double du = local.dx * scale;
      final double dv = local.dy * scale;
      base[i] = _point(face, du, dv, 0);
      if (raised) {
        top[i] = _point(face, du, dv, thickness);
      }
    }

    if (shadowPaint != null) {
      final Offset shift = _shadowShift(face, shadowOffset);
      final double spread = scale * (1 + shadowOffset * 0.35);
      final Path shadow = Path();
      for (int i = 0; i < count; i++) {
        final Offset local = outline.points[i];
        final Offset point = _point(
          face,
          local.dx * spread + shift.dx,
          local.dy * spread + shift.dy,
          0,
        );
        if (i == 0) {
          shadow.moveTo(point.dx, point.dy);
        } else {
          shadow.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(shadow..close(), shadowPaint);
    }

    // Camera-facing edges of a convex polygon form one contiguous span, so
    // the side wall costs a single extra fill.
    if (raised) {
      final double toCamX = -face.viewCenter.x;
      final double toCamY = -face.viewCenter.y;
      final double toCamZ = scene.cameraDistance - face.viewCenter.z;
      final double gu =
          face.viewU.x * toCamX + face.viewU.y * toCamY + face.viewU.z * toCamZ;
      final double gv =
          face.viewV.x * toCamX + face.viewV.y * toCamY + face.viewV.z * toCamZ;
      int start = -1;
      for (int i = 0; i < count; i++) {
        if (_visible(outline, i, gu, gv) &&
            !_visible(outline, (i - 1 + count) % count, gu, gv)) {
          start = i;
          break;
        }
      }
      if (start < 0 && _visible(outline, 0, gu, gv)) start = 0;
      int span = 0;
      while (span < count &&
          _visible(outline, (start + span) % count, gu, gv)) {
        span++;
      }
      if (start >= 0 && span > 0) {
        // A non-convex strip path would take Skia's stencil path (unavailable
        // on some Web backends); a triangle strip avoids it in one draw call.
        final List<Offset> strip = scope.stripBuffer(2 * (span + 1));
        for (int k = 0; k <= span; k++) {
          strip[2 * k] = top[(start + k) % count];
          strip[2 * k + 1] = base[(start + k) % count];
        }
        fill.color = _shadedFor(face, color, intensity, _kindSide, slot);
        canvas.drawVertices(Vertices(.triangleStrip, strip), .srcOver, fill);

        // drawVertices is not antialiased. A hairline stroke (strokeWidth 0)
        // uses Skia's AA hairline renderer: 1 device pixel, no stencil, no
        // dependence on devicePixelRatio. Both polylines must be stroked:
        // the base polyline is the sticker silhouette, the top polyline
        // blends the top/side seam. See test/aa_truth_test.dart.
        final Path silhouette = Path()..moveTo(top[start].dx, top[start].dy);
        for (int k = 1; k <= span; k++) {
          final Offset point = top[(start + k) % count];
          silhouette.lineTo(point.dx, point.dy);
        }
        for (int k = span; k >= 0; k--) {
          final Offset point = base[(start + k) % count];
          silhouette.lineTo(point.dx, point.dy);
        }
        silhouette.close();
        scope.sideStroke.color = fill.color;
        canvas.drawPath(silhouette, scope.sideStroke);
      }
    }

    final Path topPath = Path();
    for (int i = 0; i < count; i++) {
      final Offset point = top[i];
      if (i == 0) {
        topPath.moveTo(point.dx, point.dy);
      } else {
        topPath.lineTo(point.dx, point.dy);
      }
    }
    fill.color = _shadedFor(face, color, intensity, _kindSticker, slot);
    canvas.drawPath(topPath..close(), fill);

    final Image? logo = theme.centerLogo;
    if (logo != null && _carriesLogo(face)) {
      _drawLogo(canvas, logo, face, scope, intensity);
    }
  }

  /// Both checks are needed: sticker face alone would logo all 9 stickers,
  /// position alone breaks once the center cubie moves.
  bool _carriesLogo(SceneFace face) {
    final int logoFace = theme.logoFace;
    final List<int> centers = scene.state.centerCubieIndices;
    if (logoFace < 0 || logoFace >= centers.length) {
      throw ArgumentError.value(
        logoFace,
        'logoFace',
        'Must be a face index in 0 ... ${centers.length - 1}',
      );
    }
    if (face.sticker != logoFace) return false;
    return centers[logoFace] == face.cubieIndex;
  }

  /// A sticker is a perspective quadrilateral; drawImageRect is unreliable
  /// under a non-affine CTM, so split the logo into affine cells (see
  /// _logoMesh). A 4x4 mesh stays within sub-pixel of a true homography.
  void _drawLogo(
    Canvas canvas,
    Image logo,
    SceneFace face,
    _PaintScope scope,
    double intensity,
  ) {
    final double logoScale = theme.logoScale.clamp(0.0, 1.0);
    final Size imageSize = Size(logo.width.toDouble(), logo.height.toDouble());
    if (logoScale <= 0 || imageSize.isEmpty) return;

    final double stickerScale = _stickerScale;
    final double thickness = theme.stickerThickness.clamp(
      0.0,
      CubeTheme.maxStickerThickness,
    );

    // +v projects upward on screen while image y grows downward, so swap
    // the v ends or the logo appears upside down. (0,0) must be top-left.
    final Offset q0 = _point(face, -stickerScale, stickerScale, thickness);
    final Offset q1 = _point(face, stickerScale, stickerScale, thickness);
    final Offset q2 = _point(face, stickerScale, -stickerScale, thickness);
    final Offset q3 = _point(face, -stickerScale, -stickerScale, thickness);

    final Matrix4? homography = _quadHomography(q0, q1, q2, q3);
    if (homography == null) return;

    final FittedSizes fitted = applyBoxFit(
      .contain,
      imageSize,
      Size(logoScale, logoScale),
    );
    final Rect src = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & imageSize,
    );
    final Rect box = .fromCenter(
      center: const Offset(0.5, 0.5),
      width: fitted.destination.width,
      height: fitted.destination.height,
    );

    final List<Offset> outline = _outlineFor(-1, scope).points;
    final Path clip = Path();
    for (int i = 0; i < outline.length; i++) {
      final Offset? point = _applyPerspective(
        homography,
        (outline[i].dx + 1) / 2,
        (outline[i].dy + 1) / 2,
      );
      // A near-zero perspective divisor means skip this frame's logo; NaN
      // would otherwise corrupt every later command on this canvas.
      if (point == null) return;
      if (i == 0) {
        clip.moveTo(point.dx, point.dy);
      } else {
        clip.lineTo(point.dx, point.dy);
      }
    }
    clip.close();

    final Paint paint = _logoPaintFor(intensity);
    // Draw each cell into a k x k rect before transforming so sampling
    // quality stays high.
    const double k = 64;
    final double over = _logoOverscan(homography, box);

    canvas.save();
    canvas.clipPath(clip);
    for (int row = 0; row < _logoMesh; row++) {
      for (int column = 0; column < _logoMesh; column++) {
        // Expand only toward interior seams, and by the same fraction in
        // both geometry and source rect. Expanding geometry alone stretches
        // each cell's content and leaves visible 4x4 seams.
        final double f0 = column / _logoMesh + (column == 0 ? 0 : -over);
        final double f1 =
            (column + 1) / _logoMesh + (column == _logoMesh - 1 ? 0 : over);
        final double g0 = row / _logoMesh + (row == 0 ? 0 : -over);
        final double g1 =
            (row + 1) / _logoMesh + (row == _logoMesh - 1 ? 0 : over);

        final Offset? a = _applyPerspective(
          homography,
          box.left + box.width * f0,
          box.top + box.height * g0,
        );
        final Offset? b = _applyPerspective(
          homography,
          box.left + box.width * f1,
          box.top + box.height * g0,
        );
        final Offset? d = _applyPerspective(
          homography,
          box.left + box.width * f0,
          box.top + box.height * g1,
        );
        if (a == null || b == null || d == null) continue;

        final Rect srcCell = .fromLTRB(
          src.left + src.width * f0,
          src.top + src.height * g0,
          src.left + src.width * f1,
          src.top + src.height * g1,
        );

        canvas.save();
        canvas.transform(_affineMatrix(a, b, d, k).storage);
        canvas.drawImageRect(logo, srcCell, .fromLTWH(0, 0, k, k), paint);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  /// Adjacent cells must overlap by >1 screen pixel: two half-covered AA
  /// edges otherwise let the sticker show through at four-cell junctions.
  /// Use 2px / on-screen short side, capped at 0.25 to avoid crossing a
  /// whole cell.
  static double _logoOverscan(Matrix4 homography, Rect box) {
    final Offset? left = _applyPerspective(homography, box.left, box.center.dy);
    final Offset? right = _applyPerspective(
      homography,
      box.right,
      box.center.dy,
    );
    final Offset? top = _applyPerspective(homography, box.center.dx, box.top);
    final Offset? bottom = _applyPerspective(
      homography,
      box.center.dx,
      box.bottom,
    );
    if (left == null || right == null || top == null || bottom == null) {
      return 0;
    }
    final double width = (right - left).distance;
    final double height = (bottom - top).distance;
    final double smallest = math.min(width, height);
    if (smallest < 1e-3) return 0;
    return (2.0 / smallest).clamp(0.0, 0.25);
  }

  static const int _logoMesh = 4;

  /// Divide by k, not multiply: the draw target is [0,k]^2, so (k,0) must
  /// map to alongX. Multiplying would magnify the image by k^2.
  static Matrix4 _affineMatrix(
    Offset origin,
    Offset alongX,
    Offset alongY,
    double k,
  ) {
    final double ux = (alongX.dx - origin.dx) / k;
    final double uy = (alongX.dy - origin.dy) / k;
    final double vx = (alongY.dx - origin.dx) / k;
    final double vy = (alongY.dy - origin.dy) / k;
    return Matrix4(
      ux,
      uy,
      0,
      0,
      vx,
      vy,
      0,
      0,
      0,
      0,
      1,
      0,
      origin.dx,
      origin.dy,
      0,
      1,
    );
  }

  /// Return null when the perspective divisor approaches zero (near-edge-on
  /// stickers) to keep Inf/NaN out of clip paths and matrices.
  static Offset? _applyPerspective(Matrix4 h, double x, double y) {
    final Float64List m = h.storage;
    final double u = m[0] * x + m[4] * y + m[12];
    final double v = m[1] * x + m[5] * y + m[13];
    final double w = m[3] * x + m[7] * y + m[15];
    if (!w.isFinite || w.abs() < 1e-9) return null;
    final double px = u / w;
    final double py = v / w;
    if (!px.isFinite || !py.isFinite) return null;
    return Offset(px, py);
  }

  /// Solves the (g, h, 1) third row from the (1,1) corner, then backfills
  /// the remaining corners; returns null for degenerate quads.
  static Matrix4? _quadHomography(Offset p0, Offset p1, Offset p2, Offset p3) {
    final double ax = p2.dx - p1.dx;
    final double ay = p2.dy - p1.dy;
    final double bx = p2.dx - p3.dx;
    final double by = p2.dy - p3.dy;
    final double cx = p1.dx + p3.dx - p2.dx - p0.dx;
    final double cy = p1.dy + p3.dy - p2.dy - p0.dy;

    final double det = ax * by - ay * bx;
    // Scale the degeneracy threshold with quad size: a fixed epsilon
    // rejects thin but legal quads and yields w crossing zero in the square.
    final double scale = (p2 - p0).distance + 1;
    if (!det.isFinite || det.abs() < 1e-6 * scale * scale) return null;

    final double g = (cx * by - bx * cy) / det;
    final double h = (ax * cy - ay * cx) / det;
    if (!g.isFinite || !h.isFinite) return null;
    final double a = p1.dx * (g + 1) - p0.dx;
    final double b = p3.dx * (h + 1) - p0.dx;
    final double c = p0.dx;
    final double d = p1.dy * (g + 1) - p0.dy;
    final double e = p3.dy * (h + 1) - p0.dy;
    final double f = p0.dy;

    return Matrix4(a, d, 0, g, b, e, 0, h, 0, 0, 1, 0, c, f, 0, 1);
  }

  /// Modulate matches the sticker's multiply-by-intensity shading; the
  /// slight highlight above 1.0 cannot be expressed and is clamped.
  Paint _logoPaintFor(double intensity) {
    final double k = intensity.clamp(0.0, 1.0);
    return Paint()
      ..isAntiAlias = true
      ..filterQuality = .medium
      ..colorFilter = .mode(
        .from(alpha: 1, red: k, green: k, blue: k),
        .modulate,
      );
  }

  static bool _visible(_Outline outline, int index, double gu, double gv) {
    final Offset outward = outline.outward[index];
    return outward.dx * gu + outward.dy * gv > 0;
  }

  Offset _shadowShift(SceneFace face, double shadowOffset) {
    final double lu =
        face.viewU.x * lightDirection.x +
        face.viewU.y * lightDirection.y +
        face.viewU.z * lightDirection.z;
    final double lv =
        face.viewV.x * lightDirection.x +
        face.viewV.y * lightDirection.y +
        face.viewV.z * lightDirection.z;
    final double length = math.sqrt(lu * lu + lv * lv);
    if (length < 1e-6) return .zero;
    final double k = shadowOffset * _stickerScale / length;
    return Offset(-lu * k, -lv * k);
  }

  Offset _point(SceneFace face, double du, double dv, double lift) {
    return scene.projectViewXYZ(
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
  }

  Path _outlinePath(
    SceneFace face,
    List<Offset> outline,
    double scale,
    double lift,
  ) {
    final Path path = Path();
    for (int i = 0; i < outline.length; i++) {
      final Offset local = outline[i];
      final Offset projected = _point(
        face,
        local.dx * scale,
        local.dy * scale,
        lift,
      );
      if (i == 0) {
        path.moveTo(projected.dx, projected.dy);
      } else {
        path.lineTo(projected.dx, projected.dy);
      }
    }
    return path..close();
  }

  Path _pathOf(List<Offset> points) {
    final Path path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    return path..close();
  }

  /// key -1 builds a sticker outline; other keys encode body corners via
  /// _bodyKey. Cache keys include pixel scale because subdivision adapts to
  /// it.
  _Outline _outlineFor(int key, _PaintScope scope) {
    final double outer = math
        .min(theme.outerCornerRadius, scene.cornerRadius)
        .clamp(0.0, 1.0);
    final double inner = theme.bodyCornerRadius.clamp(0.0, 1.0);
    final double sticker = theme.stickerRadius.clamp(0.0, 1.0);
    final int mask = key < 0 ? 0 : key >> 1;
    final bool roundInner = key < 0 || (key & 1) == 1;
    // Quantize to 0.5px: a continuous scale would create a cache entry for
    // every tiny resize while the segment count barely changes.
    final double pixelScale = (scope.pixelScale * 2).roundToDouble() / 2;
    final _OutlineKey cacheKey = _OutlineKey(
      outer: key < 0 ? -1 : outer,
      inner: key < 0 ? -1 : inner,
      sticker: key < 0 ? sticker : -1,
      mask: mask,
      roundInner: roundInner,
      pixelScale: pixelScale,
      gap: scene.gap,
      stickerScale: _stickerScale,
    );
    final _Outline? cached = _outlineCache[cacheKey];
    if (cached != null) return cached;
    final double halfPx = pixelScale * (1 - scene.gap) / 2;
    final _Outline built = _buildOutline(cacheKey, halfPx);
    if (_outlineCache.length >= _maxOutlineCacheEntries) {
      _outlineCache.remove(_outlineCache.keys.first);
    }
    _outlineCache[cacheKey] = built;
    return built;
  }

  _Outline _buildOutline(_OutlineKey key, double halfPx) {
    final bool isSticker = key.sticker >= 0;
    final double outer = key.outer;
    final double inner = key.inner;
    final double sticker = key.sticker;
    final int mask = key.mask;
    final bool roundInner = key.roundInner;
    // Sticker outlines are later scaled by _stickerScale; body outlines
    // are not.
    final double scale = isSticker ? _stickerScale : 1;
    final List<Offset> points = <Offset>[];
    final List<Offset> outward = <Offset>[];
    for (int corner = 0; corner < 4; corner++) {
      final double r;
      if (isSticker) {
        r = sticker;
      } else if ((mask >> corner) & 1 == 1) {
        r = outer;
      } else {
        r = roundInner ? inner : 0;
      }
      final int segments = CubeScene.arcSegments(r * halfPx * scale);
      final double cx = (corner == 1 || corner == 2) ? 1 - r : -(1 - r);
      final double cy = corner >= 2 ? 1 - r : -(1 - r);
      final double start = math.pi + corner * math.pi / 2;
      for (int step = 0; step <= segments; step++) {
        final double angle = start + (step / segments) * (math.pi / 2);
        final double c = math.cos(angle);
        final double s = math.sin(angle);
        points.add(Offset(cx + r * c, cy + r * s));
        // On a convex outline the radial direction is also the outward
        // normal.
        outward.add(Offset(c, s));
      }
    }
    return _Outline(points, outward);
  }
}

class _Outline {
  const _Outline(this.points, this.outward);

  final List<Offset> points;

  final List<Offset> outward;
}

class _PaintScope {
  _PaintScope(this.theme, this.pixelScale)
    : fill = Paint()..isAntiAlias = true,
      stickerColors = theme.faceColors,
      sideStroke = Paint()
        ..style = .stroke
        ..strokeWidth = 0
        ..strokeJoin = .round
        ..isAntiAlias = true,
      shadowPaint =
          theme.stickerShadowOpacity.isFinite && theme.stickerShadowOpacity > 0
          ? (Paint()
              ..isAntiAlias = true
              ..color = const Color(0xFF000000)
                  .withValues(alpha: theme.stickerShadowOpacity.clamp(0.0, 1.0))
              ..maskFilter =
                  theme.stickerShadowBlur.isFinite &&
                      theme.stickerShadowBlur > 0
                  ? .blur(.normal, theme.stickerShadowBlur)
                  : null)
          : null;

  final CubeTheme theme;

  final double pixelScale;

  final Paint fill;

  final Paint sideStroke;

  final Paint? shadowPaint;
  final List<Color> stickerColors;

  List<Offset> _base = <Offset>[];
  List<Offset> _top = <Offset>[];
  List<Offset> _strip = <Offset>[];

  List<Offset> baseBuffer(int count) {
    if (_base.length != count) {
      _base = .filled(count, .zero);
    }
    return _base;
  }

  List<Offset> topBuffer(int count) {
    if (_top.length != count) {
      _top = .filled(count, .zero);
    }
    return _top;
  }

  List<Offset> stripBuffer(int count) {
    if (_strip.length != count) {
      _strip = .filled(count, .zero);
    }
    return _strip;
  }
}

@immutable
class _LayerKey {
  const _LayerKey(this.sceneKey, this.theme);

  final Object sceneKey;
  final CubeTheme theme;

  @override
  bool operator ==(Object other) =>
      other is _LayerKey && sceneKey == other.sceneKey && theme == other.theme;

  @override
  int get hashCode => Object.hash(sceneKey, theme);
}

class _LayerPictures {
  _LayerPictures(this.key, this.before, this.after);

  final _LayerKey key;
  final Picture before;
  final Picture after;

  void dispose() {
    before.dispose();
    after.dispose();
  }
}

/// Intensity must be part of the key: light is fixed in view space, so the
/// same world normal gets a different brightness after a view change.
@immutable
class _ShadeKey {
  const _ShadeKey(
    this.theme,
    this.bucket,
    this.slot,
    this.kind,
    this.intensity,
  );

  final CubeTheme theme;
  final int bucket;
  final int slot;
  final int kind;
  final int intensity;

  @override
  bool operator ==(Object other) =>
      other is _ShadeKey &&
      theme == other.theme &&
      bucket == other.bucket &&
      slot == other.slot &&
      kind == other.kind &&
      intensity == other.intensity;

  @override
  int get hashCode => Object.hash(theme, bucket, slot, kind, intensity);
}

/// sticker >= 0 selects a sticker outline (outer/inner ignored). pixelScale
/// determines arc subdivision, so it must be part of the key.
@immutable
class _OutlineKey {
  const _OutlineKey({
    required this.outer,
    required this.inner,
    required this.sticker,
    required this.mask,
    required this.roundInner,
    required this.pixelScale,
    required this.gap,
    required this.stickerScale,
  });

  final double outer;
  final double inner;
  final double sticker;
  final int mask;
  final bool roundInner;
  final double pixelScale;

  final double gap;
  final double stickerScale;

  @override
  bool operator ==(Object other) =>
      other is _OutlineKey &&
      outer == other.outer &&
      inner == other.inner &&
      sticker == other.sticker &&
      mask == other.mask &&
      roundInner == other.roundInner &&
      pixelScale == other.pixelScale &&
      gap == other.gap &&
      stickerScale == other.stickerScale;

  @override
  int get hashCode => Object.hash(
    outer,
    inner,
    sticker,
    mask,
    roundInner,
    pixelScale,
    gap,
    stickerScale,
  );
}
