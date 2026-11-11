import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/cube_move.dart';
import '../core/cube_state.dart';
import '../core/matrix3.dart';
import '../core/vector3.dart';

/// Holds cube state, view, and animation. Without a bound TickerProvider,
/// turns apply immediately instead of animating.
class MagicCubeController extends ChangeNotifier {
  MagicCubeController({
    int size = 3,
    this.turnDuration = const Duration(milliseconds: 220),
    this.turnCurve = Curves.easeInOutCubic,
    this.viewDuration = const Duration(milliseconds: 320),
    this.maxHistory = 500,
    double? yaw,
    double? pitch,
  }) : _view = .fromViewAngles(
         yaw: yaw ?? defaultYaw,
         pitch: pitch ?? defaultPitch,
       ) {
    _state = CubeState(size: size);
  }

  static const double defaultYaw = -0.62;

  static const double defaultPitch = 0.45;

  final Duration turnDuration;

  final Curve turnCurve;

  final Duration viewDuration;

  final int maxHistory;

  late CubeState _state;

  CubeTurn? _turn;
  bool _dragging = false;
  bool _animating = false;
  bool _processing = false;
  bool _disposed = false;

  bool _turnFromGesture = false;

  /// A free rotation matrix, not yaw/pitch Euler angles: Euler angles
  /// suffer gimbal lock near +/-90 degrees and would reverse drag
  /// direction. Incremental rotations are left-multiplied in view space.
  Mat3 _view;

  final List<CubeMove> _history = <CubeMove>[];
  final List<_Task> _queue = <_Task>[];

  TickerProvider? _vsync;
  AnimationController? _turnAnimation;
  AnimationController? _viewAnimation;

  /// Interrupted futures still complete successfully by contract; timing
  /// callers use this epoch to tell whether a scramble actually finished.
  int _taskEpoch = 0;
  int get taskEpoch => _taskEpoch;

  /// Programmed turns queue here while a gesture owns _turn.
  final Set<Completer<void>> _idleWaiters = <Completer<void>>{};

  /// Fired only when a gesture turn commits; programmed turns do not
  /// change onMove semantics.
  void Function(CubeMove)? onMoveCommitted;

  CubeState get state => _state;

  CubeTurn? get turn => _turn;

  double get turnAngle => _turn?.angle ?? 0;

  Mat3 get viewRotation => _view;

  /// Best-effort decomposition of a free rotation; do not write back as
  /// state.
  double get yaw => math.atan2(_view[2], _view[0]);

  double get pitch => math.atan2(_view[7], _view[4]);

  bool get isAnimating => _animating;

  bool get isDragging => _dragging;

  bool get isIdle => _turn == null && !_animating && !_processing;

  bool get isSolved => _turn == null && _state.isSolved;

  int get solvedFaceCount => _state.solvedFaceCount;

  List<CubeMove> get history => .unmodifiable(_history);

  int get moveCount => _history.length;

  /// The most recent widget takes over animation, disposing the old
  /// tickers.
  void bind(TickerProvider vsync) {
    if (_disposed) {
      throw StateError('Controller has been disposed and cannot be bound');
    }
    if (_vsync != null && !identical(_vsync, vsync)) {
      _turnAnimation?.dispose();
      _viewAnimation?.dispose();
      _turnAnimation = null;
      _viewAnimation = null;
      _releaseGates();
    }
    _vsync = vsync;
  }

  /// Passing vsync unbinds only if it matches, so unmounting one of two
  /// widgets sharing this controller does not dispose the other's tickers.
  void unbind([TickerProvider? vsync]) {
    if (vsync != null && _vsync != null && !identical(_vsync, vsync)) return;
    _vsync = null;
    _turnAnimation?.dispose();
    _viewAnimation?.dispose();
    _turnAnimation = null;
    _viewAnimation = null;
    // AnimationController.stop/dispose never completes forward()'s future;
    // release the pending gates explicitly.
    _releaseGates();
    _releaseIdleWaiters(force: true);
  }

  set yaw(double value) => setViewAngles(yaw: value, pitch: pitch);

  set pitch(double value) => setViewAngles(yaw: yaw, pitch: value);

  void setViewRotation(Mat3 rotation) {
    // Avoid rebuilding the widget tree on every identical animation tick.
    if (_view == rotation) return;
    _view = rotation;
    notifyListeners();
  }

  /// Setting Euler angles discards any roll from the current free pose.
  void setViewAngles({double? yaw, double? pitch}) {
    setViewRotation(
      .fromViewAngles(
        yaw: _wrapAngle(yaw ?? this.yaw),
        pitch: _wrapAngle(pitch ?? this.pitch),
      ),
    );
  }

  void orbitBy({double dx = 0, double dy = 0}) {
    if (dx == 0 && dy == 0) return;
    // Stop the view animation so its next tick cannot overwrite the
    // gesture.
    final AnimationController? animation = _viewAnimation;
    animation?.stop();
    // Release only this animation's gates; releasing all would also
    // unblock a concurrent turn animation and leave stale listeners.
    _releaseGatesOf(animation);
    setViewRotation(.rotationX(dy).multiply(.rotationY(dx)).multiply(_view));
  }

  Future<void> animateViewTo({
    double? yaw,
    double? pitch,
    Duration? duration,
    Curve? curve,
  }) {
    if (yaw == null && pitch == null) return Future<void>.value();
    return animateViewToRotation(
      .fromViewAngles(
        yaw: _wrapAngle(yaw ?? this.yaw),
        pitch: pitch ?? this.pitch,
      ),
      duration: duration,
      curve: curve,
    );
  }

  /// Interpolates about a fixed axis (a geodesic), avoiding Euler-angle
  /// detours and gimbal lock.
  Future<void> animateViewToRotation(
    Mat3 target, {
    Duration? duration,
    Curve? curve,
  }) async {
    if (_vsync == null) {
      setViewRotation(target);
      return;
    }
    final Mat3 from = _view;
    final Mat3 delta = target.multiply(from.transpose);
    final (Vec3 axis, double angle) = Mat3.axisAngleOf(delta);
    if (angle < 1e-6) {
      setViewRotation(target);
      return;
    }
    final AnimationController animation = _ensureViewAnimation();
    animation.duration = duration ?? viewDuration;
    final Curve easing = curve ?? Curves.easeOutCubic;
    void listener() {
      final double t = easing.transform(animation.value);
      setViewRotation(.rotationAround(axis, angle * t).multiply(from));
    }

    await _drive(animation, listener);
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> resetView({Duration? duration, Curve? curve}) => animateViewTo(
    yaw: defaultYaw,
    pitch: defaultPitch,
    duration: duration,
    curve: curve,
  );

  Future<void> applyMove(CubeMove move, {Duration? duration, Curve? curve}) =>
      _enqueue(_MoveTask(move, duration, curve));

  Future<void> applyMoves(
    Iterable<CubeMove> moves, {
    Duration? duration,
    Curve? curve,
  }) async {
    final List<Future<void>> futures = <Future<void>>[];
    for (final CubeMove move in moves) {
      futures.add(applyMove(move, duration: duration, curve: curve));
    }
    await Future.wait(futures);
  }

  Future<void> applyNotation(
    String sequence, {
    Duration? duration,
    Curve? curve,
  }) async {
    // Parse inside the async body so invalid notation becomes a Future
    // error rather than a synchronous throw; size must match the state.
    final List<CubeMove> moves = CubeMove.parseSequence(
      sequence,
      size: _state.size,
    );
    await applyMoves(moves, duration: duration, curve: curve);
  }

  Future<void> scramble({
    int length = 20,
    Duration? duration,
    math.Random? random,
  }) async {
    final List<CubeMove> moves = CubeMove.randomScramble(
      length: length,
      size: _state.size,
      random: random,
    );
    await applyMoves(
      moves,
      duration: duration ?? const Duration(milliseconds: 130),
    );
  }

  void clearHistory() {
    if (_history.isEmpty) return;
    _history.clear();
    notifyListeners();
  }

  Future<void> undo({Duration? duration, Curve? curve}) async {
    if (_history.isEmpty) return;
    final CubeMove last = _history.last;
    await _enqueue(
      _MoveTask(
        last.inverse,
        duration,
        curve,
        record: false,
        onCommitted: _dropLastHistory,
      ),
    );
  }

  /// Each history entry is dropped only after its inverse commits;
  /// clearing up front would leave a partly solved cube with nothing left
  /// to undo.
  Future<void> undoAll({Duration? duration, Curve? curve}) async {
    final List<CubeMove> moves = .of(_history);
    final List<Future<void>> futures = <Future<void>>[];
    for (final CubeMove move in moves.reversed) {
      futures.add(
        _enqueue(
          _MoveTask(
            move.inverse,
            duration,
            curve,
            record: false,
            onCommitted: _dropLastHistory,
          ),
        ),
      );
    }
    await Future.wait(futures);
  }

  void _dropLastHistory() {
    if (_history.isNotEmpty) _history.removeLast();
  }

  void reset() {
    _taskEpoch++;
    _cancelQueue();
    _stopAnimations();
    _dragging = false;
    _animating = false;
    _clearTurn();
    _history.clear();
    _state.reset();
    notifyListeners();
  }

  /// stop() makes forward() complete with TickerCanceled; every caller
  /// already catches it. Without this, the ticker keeps isIdle false for
  /// the full duration and pending futures never return.
  void _stopAnimations() {
    _turnAnimation?.stop();
    _viewAnimation?.stop();
    _releaseGates();
  }

  /// forward() does not complete when stopped (reproducible in flutter
  /// test), so every animation waits on a Completer instead. Gates are
  /// grouped per controller so orbitBy can release view animations only.
  final Map<AnimationController, Set<Completer<void>>> _gates =
      <AnimationController, Set<Completer<void>>>{};

  Future<void> _drive(AnimationController animation, VoidCallback onTick) {
    final Completer<void> gate = Completer<void>();
    void tick() {
      onTick();
      // Completion must be judged by progress, not status: assigning
      // value = 0 resets status to dismissed and would release every
      // tween but the first before it starts.
      if (animation.value >= 1 - 1e-9) _release(gate);
    }

    animation.value = 0;
    animation.addListener(tick);
    _gates.putIfAbsent(animation, () => <Completer<void>>{}).add(gate);
    unawaited(
      animation.forward().then<void>((void _) {}, onError: (Object _) {}),
    );
    return gate.future.whenComplete(() {
      final Set<Completer<void>>? pending = _gates[animation];
      pending?.remove(gate);
      if (pending != null && pending.isEmpty) _gates.remove(animation);
      animation.removeListener(tick);
    });
  }

  static void _release(Completer<void> gate) {
    if (!gate.isCompleted) gate.complete();
  }

  void _releaseGates() {
    if (_gates.isEmpty) return;
    final List<Completer<void>> pending = <Completer<void>>[
      for (final Set<Completer<void>> set in _gates.values) ...set,
    ];
    _gates.clear();
    for (final Completer<void> gate in pending) {
      _release(gate);
    }
  }

  void _releaseGatesOf(AnimationController? animation) {
    if (animation == null) return;
    final Set<Completer<void>>? pending = _gates.remove(animation);
    if (pending == null) return;
    for (final Completer<void> gate in pending) {
      _release(gate);
    }
  }

  Future<void> _waitUntilIdle() {
    if (!_dragging && _turn == null) return Future<void>.value();
    final Completer<void> waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  void _releaseIdleWaiters({bool force = false}) {
    if (!force && (_dragging || _turn != null)) return;
    if (_idleWaiters.isEmpty) return;
    final List<Completer<void>> waiters = List<Completer<void>>.of(
      _idleWaiters,
    );
    _idleWaiters.clear();
    for (final Completer<void> waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void _clearTurn() {
    _turn = null;
    _releaseIdleWaiters();
  }

  void stopAnimation() {
    _taskEpoch++;
    _cancelQueue();
    _stopAnimations();
    final CubeTurn? current = _turn;
    final bool fromGesture = _turnFromGesture;
    _dragging = false;
    _animating = false;
    _clearTurn();
    if (current != null) {
      final int quarters = current.snappedQuarterTurns;
      if (quarters != 0) {
        final CubeMove move = current.toMove(quarters);
        if (fromGesture) {
          _commitGestureMove(move);
        } else {
          _applyMove(move);
        }
      }
    }
    notifyListeners();
  }

  void beginTurn({required CubeAxis axis, required int layer}) {
    if (!isIdle || _disposed) return;
    if (layer < 0 || layer >= _state.size) {
      throw RangeError.range(
        layer,
        0,
        _state.size - 1,
        'layer',
        'Layer index out of range',
      );
    }
    _dragging = true;
    _turnFromGesture = true;
    _turn = CubeTurn(axis: axis, layer: layer);
    notifyListeners();
  }

  void updateTurn(double angle) {
    if (!_dragging || _turn == null) return;
    if (!angle.isFinite) {
      throw ArgumentError.value(angle, 'angle', 'Angle must be finite');
    }
    _turn = _turn!.withAngle(angle);
    notifyListeners();
  }

  /// Tweens back to 0 without recording history. Zeroing the angle first
  /// would snap the layer back and leave no distance to animate.
  Future<void> cancelTurn({Duration? duration, Curve? curve}) async {
    if (!_dragging) return;
    _dragging = false;
    final CubeTurn? current = _turn;
    if (current == null) {
      notifyListeners();
      return;
    }
    if (_settleImmediately(current, 0, duration)) {
      // The immediate path must also clear _turn, or isIdle/isSolved stay
      // false forever (no vsync, zero duration, or unmount mid-gesture).
      _animating = false;
      _clearTurn();
      notifyListeners();
      return;
    }

    _animating = true;
    notifyListeners();
    await _animateTurnTo(0, duration ?? turnDuration, curve);
    _animating = false;
    _clearTurn();
    notifyListeners();
  }

  /// Skip the tween when there is no vsync or the target is already
  /// reached; otherwise the still frame looks like a hitch.
  bool _settleImmediately(CubeTurn current, double target, Duration? duration) {
    if (_vsync == null) return true;
    if ((duration ?? turnDuration) <= .zero) return true;
    return (target - current.angle).abs() < 1e-9;
  }

  Duration _resolveDuration(Duration? requested, double distance) {
    final Duration base = requested ?? turnDuration;
    if (base <= .zero) return base;
    final double ratio = (distance.abs() / (math.pi / 2)).clamp(0.3, 1.0);
    return Duration(microseconds: (base.inMicroseconds * ratio).round());
  }

  /// angularVelocity lets the settle tween continue the finger's
  /// momentum.
  Future<void> endTurn({
    Duration? duration,
    Curve? curve,
    double angularVelocity = 0,
  }) async {
    if (!_dragging) return;
    _dragging = false;
    final CubeTurn? current = _turn;
    if (current == null) {
      _clearTurn();
      notifyListeners();
      return;
    }
    // Normalized quarters flip -180 deg to +180 deg and replay a full turn.
    final double target = current.nearestRightAngle;
    final CubeMove move = current.toMove(current.snappedQuarterTurns);
    final Duration animationDuration = duration ?? turnDuration;
    if (_vsync == null || animationDuration <= .zero) {
      _clearTurn();
      if (!move.isNoop) _commitGestureMove(move);
      notifyListeners();
      return;
    }
    if ((target - current.angle).abs() < 1e-9) {
      _animating = false;
      _clearTurn();
      if (!move.isNoop) _commitGestureMove(move);
      notifyListeners();
      return;
    }

    _animating = true;
    notifyListeners();
    await _animateTurnTo(
      target,
      animationDuration,
      curve,
      angularVelocity: angularVelocity,
    );
    final bool interrupted = _turn == null || _disposed;
    _animating = false;
    _clearTurn();
    if (!move.isNoop && !interrupted) {
      _commitGestureMove(move);
    }
    notifyListeners();
  }

  /// Interrupted tasks resume after await; guard against notifying a
  /// disposed ChangeNotifier.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _cancelQueue();
    unbind();
    onMoveCommitted = null;
    _disposed = true;
    super.dispose();
  }

  Future<void> _enqueue(_Task task) {
    if (_disposed) {
      task.complete();
      return task.completer.future;
    }
    _queue.add(task);
    _pump();
    return task.completer.future;
  }

  Future<void> _pump() async {
    if (_processing) return;
    _processing = true;
    notifyListeners();
    while (_queue.isNotEmpty) {
      if (_dragging || _turn != null) {
        await _waitUntilIdle();
      }
      if (_disposed) {
        // Still complete canceled tasks so callers do not hang.
        _cancelQueue();
        break;
      }
      final _Task task = _queue.removeAt(0);
      try {
        await _runTask(task);
        task.complete();
      } catch (error) {
        task.fail(error);
      }
    }
    _processing = false;
    notifyListeners();
  }

  Future<void> _runTask(_Task task) async {
    switch (task) {
      case _MoveTask():
        await _animateMove(
          task.move,
          task.duration,
          task.curve,
          task.record,
          onCommitted: task.onCommitted,
        );
      case _ActionTask():
        task.action();
        notifyListeners();
    }
  }

  Future<void> _animateMove(
    CubeMove move,
    Duration? duration,
    Curve? curve,
    bool record, {
    void Function()? onCommitted,
  }) async {
    final CubeMove normalized = CubeMove(
      axis: move.axis,
      layer: move.layer,
      quarterTurns: move.normalizedQuarterTurns,
      wholeCube: move.wholeCube,
    );
    if (normalized.isNoop) return;
    final Duration animationDuration = duration ?? turnDuration;
    if (_vsync == null || animationDuration <= .zero) {
      if (_applyMove(normalized, record: record)) onCommitted?.call();
      notifyListeners();
      return;
    }

    _turnFromGesture = false;
    _turn = CubeTurn(
      axis: normalized.axis,
      layer: normalized.layer,
      wholeCube: normalized.wholeCube,
    );
    _animating = true;
    notifyListeners();
    await _animateTurnTo(normalized.radians, animationDuration, curve);
    final bool interrupted = _turn == null || _disposed;
    _animating = false;
    _clearTurn();
    if (!interrupted) {
      if (_applyMove(normalized, record: record)) onCommitted?.call();
    }
    notifyListeners();
  }

  Future<void> _animateTurnTo(
    double target,
    Duration requested,
    Curve? curve, {
    double angularVelocity = 0,
  }) async {
    final CubeTurn? current = _turn;
    if (current == null || _vsync == null) return;
    final AnimationController animation = _ensureTurnAnimation();
    final double from = current.angle;
    final Duration duration = _resolveDuration(requested, target - from);
    animation.duration = duration;
    final Curve easing = _settleEasing(
      requested: curve,
      angularVelocity: angularVelocity,
      distance: target - from,
      duration: duration,
    );
    void listener() {
      if (_turn == null) return;
      final double t = easing.transform(animation.value);
      _turn = _turn!.withAngle(from + (target - from) * t);
      notifyListeners();
    }

    await _drive(animation, listener);
  }

  /// easeInOut curves start at zero velocity, which looks like a hitch
  /// after a flick; use _VelocitySettle to match the release velocity.
  Curve _settleEasing({
    required Curve? requested,
    required double angularVelocity,
    required double distance,
    required Duration duration,
  }) {
    if (angularVelocity == 0 || distance.abs() < 1e-9) {
      return requested ?? turnCurve;
    }
    final double seconds =
        duration.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return requested ?? turnCurve;
    final double slope = (angularVelocity * seconds / distance).clamp(
      -1.5,
      2.5,
    );
    return _VelocitySettle(slope);
  }

  AnimationController _ensureTurnAnimation() {
    return _turnAnimation ??= AnimationController(
      vsync: _vsync!,
      duration: turnDuration,
    );
  }

  AnimationController _ensureViewAnimation() {
    return _viewAnimation ??= AnimationController(
      vsync: _vsync!,
      duration: viewDuration,
    );
  }

  bool _applyMove(CubeMove move, {bool record = true}) {
    final bool changed = _state.applyMove(move);
    if (!changed) return false;
    if (record) {
      _history.add(move);
      if (_history.length > maxHistory) {
        _history.removeAt(0);
      }
    }
    return true;
  }

  void _commitGestureMove(CubeMove move) {
    if (_applyMove(move)) onMoveCommitted?.call(move);
  }

  void _cancelQueue() {
    // Canceled tasks still complete successfully; bump the epoch so
    // timers can detect an unfinished run.
    _taskEpoch++;
    if (_queue.isEmpty) return;
    final List<_Task> tasks = .of(_queue);
    _queue.clear();
    for (final _Task task in tasks) {
      task.complete();
    }
  }

  static double _wrapAngle(double value) {
    if (!value.isFinite) return 0;
    const double twoPi = math.pi * 2;
    final double wrapped = (value + math.pi) % twoPi;
    return (wrapped < 0 ? wrapped + twoPi : wrapped) - math.pi;
  }
}

/// Cubic satisfying p(0)=0, p'(0)=k, p(1)=1, p'(1)=0, where k is the
/// release velocity in normalized time. k < 0 briefly moves backwards,
/// matching a decelerate-and-return flick.
class _VelocitySettle extends Curve {
  const _VelocitySettle(this.slope);

  final double slope;

  @override
  double transform(double t) {
    final double k = slope;
    return (k - 2) * t * t * t + (3 - 2 * k) * t * t + k * t;
  }
}

sealed class _Task {
  final Completer<void> completer = Completer<void>();

  Future<void> get future => completer.future;

  void complete() {
    if (!completer.isCompleted) completer.complete();
  }

  void fail(Object error) {
    if (!completer.isCompleted) completer.completeError(error);
  }
}

final class _MoveTask extends _Task {
  _MoveTask(
    this.move,
    this.duration,
    this.curve, {
    this.record = true,
    this.onCommitted,
  });

  final CubeMove move;
  final Duration? duration;
  final Curve? curve;
  final bool record;

  final void Function()? onCommitted;
}

final class _ActionTask extends _Task {
  _ActionTask(this.action);

  final VoidCallback action;
}
