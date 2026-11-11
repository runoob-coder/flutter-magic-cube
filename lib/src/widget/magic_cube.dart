import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../core/cube_move.dart';
import '../core/matrix3.dart';
import '../core/vector3.dart';
import '../render/cube_painter.dart';
import '../render/cube_scene.dart';
import '../theme/cube_theme.dart';
import 'magic_cube_controller.dart';

/// Dragging on the cube turns the touched layer; dragging outside it orbits
/// the whole cube. Both can be disabled independently.
class MagicCube extends StatefulWidget {
  const MagicCube({
    super.key,
    this.controller,
    this.theme = const CubeTheme(),
    this.zoom = 1,
    this.cameraDistance = 9.5,
    this.fitRadius = 2.45,
    this.interactive = true,
    this.enableLayerTurns = true,
    this.enableWholeRotation = true,
    this.inertia = true,
    this.dragThreshold = 8,
    this.orbitSensitivity = 0.0075,
    this.turnSensitivity = 1,
    this.inertiaFriction = 7,
    this.inertiaDuration = const Duration(milliseconds: 520),
    this.maxInertiaVelocity = 8,
    this.turnDuration,
    this.turnCurve,
    this.centerLogo,
    this.logoFace,
    this.logoScale,
    this.onMove,
    this.onViewChanged,
  });

  final MagicCubeController? controller;

  final CubeTheme theme;

  /// Shortcut for theme.centerLogo; the caller owns and must dispose the
  /// image.
  final ui.Image? centerLogo;

  final int? logoFace;

  final double? logoScale;

  final double zoom;

  final double cameraDistance;

  final double fitRadius;

  final bool interactive;

  final bool enableLayerTurns;

  final bool enableWholeRotation;

  final bool inertia;

  final double dragThreshold;

  final double orbitSensitivity;

  final double turnSensitivity;

  /// Total inertial travel is velocity / inertiaFriction.
  final double inertiaFriction;

  final Duration inertiaDuration;

  final double maxInertiaVelocity;

  final Duration? turnDuration;

  final Curve? turnCurve;

  final ValueChanged<CubeMove>? onMove;

  final ValueChanged<CubeView>? onViewChanged;

  @override
  State<MagicCube> createState() => _MagicCubeState();
}

/// Closest yaw/pitch decomposition of a free rotation: suitable for
/// display, not for restoring exact poses (use viewRotation/setViewRotation).
class CubeView {
  const CubeView({required this.yaw, required this.pitch});

  final double yaw;

  final double pitch;
}

class _MagicCubeState extends State<MagicCube> with TickerProviderStateMixin {
  MagicCubeController? _internalController;
  MagicCubeController? _attached;

  Size _viewport = .zero;
  _PendingDrag? _pending;
  _LayerDrag? _layerDrag;
  bool _orbiting = false;

  _CubeDrag? _drag;

  _CubeDrag? _secondDrag;

  bool _twoFinger = false;

  /// Multi-drag recognizers report global positions only; the RenderBox
  /// converts them to the CubeScene viewport frame.
  final GlobalKey _gestureKey = GlobalKey();

  Offset _toLocal(Offset global) {
    final RenderObject? object = _gestureKey.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return global;
    return object.globalToLocal(global);
  }

  AnimationController? _orbitAnimation;

  double _lastYaw = 0;
  double _lastPitch = 0;

  MagicCubeController get _controller => _attached!;

  /// withLogo returns the original theme when all shortcuts are null, so
  /// the renderer keeps its cache hits.
  CubeTheme get _resolvedTheme => widget.theme.withLogo(
    centerLogo: widget.centerLogo,
    logoFace: widget.logoFace,
    logoScale: widget.logoScale,
  );

  /// Pictures hold native resources and shade entries are theme-keyed;
  /// release both when the last cube unmounts.
  static int _activeInstances = 0;

  static void _releaseRenderCachesIfIdle() {
    _activeInstances--;
    if (_activeInstances > 0) return;
    _activeInstances = 0;
    CubePainter.disposeCaches();
    CubeScene.disposeSceneCache();
  }

  @override
  void initState() {
    super.initState();
    _activeInstances++;
    _attach(null);
    _lastYaw = _controller.yaw;
    _lastPitch = _controller.pitch;
  }

  @override
  void didUpdateWidget(covariant MagicCube oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactive && !widget.interactive) {
      // Drop the gesture immediately, or its end would still commit a move.
      _resetGesture();
      _orbitAnimation?.stop();
      unawaited(_controller.cancelTurn());
    }
    if (oldWidget.controller != widget.controller) {
      final MagicCubeController? previous =
          oldWidget.controller ?? _internalController;
      if (identical(previous?.onMoveCommitted, _handleCommitted)) {
        previous?.onMoveCommitted = null;
      }
      // Unbind first so the old controller stops holding this State as
      // vsync; passing this keeps other widgets sharing it unaffected.
      previous?.unbind(this);
      _attach(previous);
    }
  }

  @override
  void dispose() {
    // Cancel gestures before unbinding: a later Drag.cancel would run
    // without vsync and leave a permanent ghost turn.
    _resetGesture();
    _orbitAnimation?.stop();
    _attached?.removeListener(_handleControllerChanged);
    if (identical(_attached?.onMoveCommitted, _handleCommitted)) {
      _attached?.onMoveCommitted = null;
    }
    _attached?.unbind(this);
    _internalController?.dispose();
    _orbitAnimation?.dispose();
    _releaseRenderCachesIfIdle();
    super.dispose();
  }

  void _attach(MagicCubeController? previous) {
    previous?.removeListener(_handleControllerChanged);
    if (widget.controller != null) {
      if (_internalController != null) {
        _internalController!.dispose();
        _internalController = null;
      }
      _attached = widget.controller;
    } else {
      _internalController ??= MagicCubeController(
        turnDuration: widget.turnDuration ?? const Duration(milliseconds: 220),
        turnCurve: widget.turnCurve ?? Curves.easeInOutCubic,
      );
      _attached = _internalController;
    }
    _controller
      ..bind(this)
      ..addListener(_handleControllerChanged);
    // The controller reports only committed moves, avoiding extra events
    // after a reset or stop.
    _controller.onMoveCommitted = _handleCommitted;
    _lastYaw = _controller.yaw;
    _lastPitch = _controller.pitch;
  }

  void _handleCommitted(CubeMove move) {
    widget.onMove?.call(move);
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    final double yaw = _controller.yaw;
    final double pitch = _controller.pitch;
    if (yaw != _lastYaw || pitch != _lastPitch) {
      _lastYaw = yaw;
      _lastPitch = pitch;
      widget.onViewChanged?.call(CubeView(yaw: yaw, pitch: pitch));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = _resolveSide(constraints);
        _viewport = Size(side, side);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: RawGestureDetector(
              key: _gestureKey,
              behavior: .translucent,
              gestures: <Type, GestureRecognizerFactory>{
                // Per-pointer recognizer: a plain pan averages pointers,
                // so a second finger would jump the position and misread a
                // layer turn as an orbit.
                ImmediateMultiDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      ImmediateMultiDragGestureRecognizer
                    >(() => ImmediateMultiDragGestureRecognizer(), (
                      ImmediateMultiDragGestureRecognizer instance,
                    ) {
                      instance.onStart = _startDrag;
                    }),
              },
              child: RepaintBoundary(
                // CustomPaint's isComplex/willChange do not create a
                // compositing layer; an explicit RepaintBoundary is needed
                // to isolate the per-frame repaint.
                child: CustomPaint(
                  isComplex: true,
                  willChange: true,
                  painter: CubePainter(
                    scene: _buildScene(),
                    theme: _resolvedTheme,
                  ),
                  size: Size(side, side),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static const double _unboundedSide = 320;

  double _resolveSide(BoxConstraints constraints) {
    final double width = constraints.maxWidth;
    final double height = constraints.maxHeight;
    if (width.isInfinite && height.isInfinite) return _unboundedSide;
    if (height.isInfinite) return width;
    if (width.isInfinite) return height;
    return math.min(width, height);
  }

  CubeScene _buildScene() => CubeScene(
    state: _controller.state,
    turn: _controller.turn,
    yaw: _controller.yaw,
    pitch: _controller.pitch,
    view: _controller.viewRotation,
    viewport: _viewport,
    gap: widget.theme.gap,
    cornerRadius: widget.theme.outerCornerRadius,
    zoom: widget.zoom,
    cameraDistance: widget.cameraDistance,
    fitRadius: widget.fitRadius,
    stickerScale: _resolvedTheme.stickerScale,
  );

  Drag? _startDrag(Offset globalPosition) {
    if (!widget.interactive) return null;
    if (_drag == null) {
      _orbitAnimation?.stop();
      final Offset position = _toLocal(globalPosition);
      final CubeScene scene = _buildScene();
      _pending = _PendingDrag(
        scene: scene,
        start: position,
        hit: scene.pick(position),
      );
      return _drag = _CubeDrag(this);
    }
    if (_secondDrag != null || !widget.enableWholeRotation) return null;
    _switchToTwoFingerOrbit();
    return _secondDrag = _CubeDrag(this);
  }

  void _switchToTwoFingerOrbit() {
    final _LayerDrag? layer = _layerDrag;
    _layerDrag = null;
    _pending = null;
    _twoFinger = true;
    if (layer != null) {
      unawaited(
        _controller.cancelTurn(
          duration: widget.turnDuration,
          curve: widget.turnCurve,
        ),
      );
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!widget.interactive) return;
    if (_twoFinger) {
      // Each finger contributes half the delta, following the two-finger
      // midpoint; opposing pinch motions cancel.
      _orbitBy(details.delta * 0.5);
      return;
    }
    final _LayerDrag? layerDrag = _layerDrag;
    if (layerDrag != null) {
      _controller.updateTurn(
        layerDrag.angleFor(_toLocal(details.globalPosition)) *
            widget.turnSensitivity,
      );
      return;
    }
    if (_orbiting) {
      _orbitBy(details.delta);
      return;
    }
    final _PendingDrag? pending = _pending;
    if (pending == null) return;
    final Offset position = _toLocal(details.globalPosition);
    final Offset delta = position - pending.start;
    if (delta.distance < widget.dragThreshold) return;

    final _LayerDrag? drag = _createLayerDrag(pending, delta);
    if (drag != null) {
      _layerDrag = drag;
      _pending = null;
      _controller.beginTurn(axis: drag.axis, layer: drag.layer);
      _controller.updateTurn(drag.angleFor(position) * widget.turnSensitivity);
    } else if (widget.enableWholeRotation) {
      _pending = null;
      _orbiting = true;
      _orbitBy(delta);
    } else {
      _pending = null;
    }
  }

  void _handlePanEnd(_CubeDrag source, DragEndDetails details) {
    final _LayerDrag? drag = _layerDrag;
    final bool wasOrbiting = _orbiting || _twoFinger;
    // Lifting any finger ends the whole gesture; remaining pointers must
    // be pressed again.
    _resetGesture();
    if (!widget.interactive) return;
    if (drag != null) {
      unawaited(
        _settleTurn(drag.angularVelocityFor(details.velocity.pixelsPerSecond)),
      );
      return;
    }
    if (wasOrbiting) _startInertia(details.velocity.pixelsPerSecond);
  }

  void _resetGesture() {
    _drag = null;
    _secondDrag = null;
    _twoFinger = false;
    _orbiting = false;
    _pending = null;
    _layerDrag = null;
  }

  Future<void> _settleTurn(double angularVelocity) async {
    await _controller.endTurn(
      duration: widget.turnDuration,
      curve: widget.turnCurve,
      angularVelocity: angularVelocity,
    );
  }

  void _handlePanCancel(_CubeDrag source) {
    final _LayerDrag? drag = _layerDrag;
    _resetGesture();
    if (drag != null) {
      unawaited(
        _controller.cancelTurn(
          duration: widget.turnDuration,
          curve: widget.turnCurve,
        ),
      );
    }
  }

  void _orbitBy(Offset delta) {
    if (!widget.enableWholeRotation) return;
    if (delta.distanceSquared == 0) return;
    _controller.orbitBy(
      dx: delta.dx * widget.orbitSensitivity,
      dy: delta.dy * widget.orbitSensitivity,
    );
  }

  /// Avoid FrictionSimulation: its drag argument is an exponential base
  /// (0 < drag < 1); values > 1 accelerate and move the endpoint backwards.
  void _startInertia(Offset pixelsPerSecond) {
    if (!widget.inertia || !widget.interactive) return;
    if (!pixelsPerSecond.dx.isFinite || !pixelsPerSecond.dy.isFinite) return;
    final double sensitivity = widget.orbitSensitivity.isFinite
        ? widget.orbitSensitivity
        : 0.0075;
    final double maxVelocity =
        widget.maxInertiaVelocity.isFinite && widget.maxInertiaVelocity > 0
        ? widget.maxInertiaVelocity
        : 8;
    final double friction =
        widget.inertiaFriction.isFinite && widget.inertiaFriction > 0
        ? widget.inertiaFriction
        : 7;
    final Duration duration = widget.inertiaDuration > .zero
        ? widget.inertiaDuration
        : const Duration(milliseconds: 520);
    final double vx = (pixelsPerSecond.dx * sensitivity).clamp(
      -maxVelocity,
      maxVelocity,
    );
    final double vy = (pixelsPerSecond.dy * sensitivity).clamp(
      -maxVelocity,
      maxVelocity,
    );
    if (vx.abs() < 0.05 && vy.abs() < 0.05) return;

    final Mat3 base = _controller.viewRotation;
    final double distanceX = vx / friction;
    final double distanceY = vy / friction;
    final Curve curve = _ExponentialDecay(
      friction,
      duration.inMicroseconds / Duration.microsecondsPerSecond,
    );
    final AnimationController animation = _orbitAnimation ??=
        AnimationController(vsync: this);
    animation.duration = duration;
    void listener() {
      if (!mounted) return;
      final double t = curve.transform(animation.value);
      _controller.setViewRotation(
        .rotationX(
          distanceY * t,
        ).multiply(.rotationY(distanceX * t)).multiply(base),
      );
    }

    animation.addListener(listener);
    animation.value = 0;
    unawaited(_runInertia(animation, listener));
  }

  Future<void> _runInertia(
    AnimationController animation,
    VoidCallback listener,
  ) async {
    try {
      await animation.forward(from: 0);
    } on TickerCanceled {
      // A new gesture interrupted the animation.
    } finally {
      animation.removeListener(listener);
    }
  }

  /// With face normal n and in-face drag axis u, the turn axis is n x u;
  /// its positive direction moves the sticker along u.
  _LayerDrag? _createLayerDrag(_PendingDrag pending, Offset delta) {
    final SceneHit? hit = pending.hit;
    if (hit == null || !widget.enableLayerTurns || !_controller.isIdle) {
      return null;
    }
    final CubeScene scene = pending.scene;
    final Vec3 normal = hit.worldNormal;
    final CubeAxis normalAxis = normal.nearestAxis;

    CubeAxis bestAxis = normalAxis;
    double bestScore = 0;
    Offset bestDirection = .zero;
    for (final CubeAxis axis in perpendicularAxes(normalAxis)) {
      final Offset direction = _axisScreenDirection(
        scene,
        hit.worldCenter,
        axis,
      );
      final double score = delta.dx * direction.dx + delta.dy * direction.dy;
      if (score.abs() > bestScore.abs()) {
        bestScore = score;
        bestAxis = axis;
        bestDirection = direction;
      }
    }
    if (bestScore == 0 || bestDirection == Offset.zero) return null;

    final bool positive = bestScore > 0;
    final Vec3 u = positive
        ? kAxisVectors[bestAxis]!
        : -kAxisVectors[bestAxis]!;
    final Offset direction = positive ? bestDirection : -bestDirection;

    final Vec3 rotationAxis = normal.cross(u).snapped;
    final CubeAxis axis = rotationAxis.nearestAxis;
    final int sign = rotationAxis.dot(kAxisVectors[axis]!).round();
    if (sign == 0) return null;

    // Layer indices are measured along the positive axis. rotationAxis
    // can be negative, and dotting with it would mirror the layer to the
    // far side (invisible for the middle layer).
    final int layerCoordinate = kAxisVectors[axis]!
        .dot(scene.cubies[hit.cubieIndex].position)
        .round();
    final int layer = layerCoordinate + _controller.state.halfExtent;

    final Offset origin = scene.project(const .zero());
    final Offset axisPoint = scene.project(kAxisVectors[axis]! * 0.5);
    final double axisLength = (axisPoint - origin).distance;
    final Offset axisDirection = axisLength > 1e-6
        ? (axisPoint - origin) / axisLength
        : .zero;
    final Offset toTouch = pending.start - origin;
    final double along =
        toTouch.dx * axisDirection.dx + toTouch.dy * axisDirection.dy;
    final Offset perpendicular =
        toTouch - Offset(axisDirection.dx * along, axisDirection.dy * along);
    final double radius = math.max(perpendicular.distance, 24);

    return _LayerDrag(
      axis: axis,
      layer: layer,
      direction: direction,
      radius: radius,
      start: pending.start,
      sign: sign,
    );
  }

  Offset _axisScreenDirection(CubeScene scene, Vec3 center, CubeAxis axis) {
    final Offset from = scene.project(center);
    final Offset to = scene.project(center + kAxisVectors[axis]! * 0.35);
    final Offset delta = to - from;
    final double length = delta.distance;
    if (length < 1e-6) return .zero;
    return delta / length;
  }
}

class _PendingDrag {
  _PendingDrag({required this.scene, required this.start, required this.hit});

  final CubeScene scene;
  final Offset start;
  final SceneHit? hit;
}

class _CubeDrag extends Drag {
  _CubeDrag(this.owner);

  final _MagicCubeState owner;

  @override
  void update(DragUpdateDetails details) => owner._handlePanUpdate(details);

  @override
  void end(DragEndDetails details) => owner._handlePanEnd(this, details);

  @override
  void cancel() => owner._handlePanCancel(this);
}

class _LayerDrag {
  _LayerDrag({
    required this.axis,
    required this.layer,
    required this.direction,
    required this.radius,
    required this.start,
    required this.sign,
  });

  final CubeAxis axis;
  final int layer;

  final Offset direction;

  final double radius;

  final Offset start;

  final int sign;

  double angleFor(Offset current) {
    final Offset delta = current - start;
    final double along = delta.dx * direction.dx + delta.dy * direction.dy;
    final double theta = (along / radius) * sign;
    return theta.clamp(-math.pi, math.pi);
  }

  double angularVelocityFor(Offset pixelsPerSecond) {
    final double along =
        pixelsPerSecond.dx * direction.dx + pixelsPerSecond.dy * direction.dy;
    return (along / radius) * sign;
  }
}

class _ExponentialDecay extends Curve {
  const _ExponentialDecay(this.rate, this.seconds);

  final double rate;

  final double seconds;

  @override
  double transform(double t) {
    final double total = 1 - math.exp(-rate * seconds);
    if (total <= 0) return t;
    return (1 - math.exp(-rate * seconds * t)) / total;
  }
}
