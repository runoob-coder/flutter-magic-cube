import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:magic_cube/magic_cube.dart';

enum SessionPhase { idle, scrambling, solving, finished }

class CubeSession extends ChangeNotifier {
  CubeSession(this.controller, {this.scrambleLength = 20}) {
    controller.addListener(_onControllerChanged);
  }

  final MagicCubeController controller;

  int scrambleLength;

  SessionPhase _phase = SessionPhase.idle;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  final List<Duration> _records = <Duration>[];
  Duration? _lastRecord;
  bool _bestTime = false;
  bool _disposed = false;

  /// Pending finish before the 500ms guard elapses; retried by the timer.
  bool _pendingFinish = false;

  SessionPhase get phase => _phase;

  Duration get elapsed => _elapsed;

  Duration? get lastRecord => _lastRecord;

  bool get isBestTime => _bestTime;

  List<Duration> get records => List<Duration>.unmodifiable(_records);

  int get totalSolves => _records.length;

  Duration? get best => _records.isEmpty
      ? null
      : _records.reduce((Duration a, Duration b) => a < b ? a : b);

  Duration? get worst => _records.isEmpty
      ? null
      : _records.reduce((Duration a, Duration b) => a > b ? a : b);

  /// Trimmed mean of the last 5 solves (best and worst removed).
  Duration? get averageOf5 => _averageOf(5);

  Duration? get averageOf12 => _averageOf(12);

  Future<void> start({int? length}) async {
    if (_phase == SessionPhase.scrambling) return;
    if (length != null) scrambleLength = length;
    _bestTime = false;
    _lastRecord = null;
    _elapsed = Duration.zero;
    _pendingFinish = false;
    _setPhase(SessionPhase.scrambling);
    // An interrupted scramble still completes; compare taskEpoch so
    // timing never starts on an unscrambled cube.
    final int epoch = controller.taskEpoch;
    await controller.scramble(
      length: scrambleLength,
      duration: const Duration(milliseconds: 110),
    );
    if (_disposed || _phase != SessionPhase.scrambling) return;
    if (controller.taskEpoch != epoch) {
      abort();
      return;
    }
    _setPhase(SessionPhase.solving);
    _stopwatch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 32), (_) {
      _elapsed = _stopwatch.elapsed;
      notifyListeners();
      _tryFinish();
    });
  }

  void abort() {
    _pendingFinish = false;
    _stopTimer();
    _setPhase(SessionPhase.idle);
  }

  @override
  void dispose() {
    _stopTimer();
    controller.removeListener(_onControllerChanged);
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  void _onControllerChanged() {
    if (_phase != SessionPhase.solving) return;
    if (!controller.isSolved) {
      _pendingFinish = false;
      return;
    }
    _pendingFinish = true;
    _tryFinish();
  }

  /// A solve inside the 500ms guard is deferred, not dropped; an early
  /// return would leave no later trigger and lose the record.
  void _tryFinish() {
    if (!_pendingFinish || _phase != SessionPhase.solving) return;
    if (_stopwatch.elapsed < const Duration(milliseconds: 500)) return;
    _pendingFinish = false;
    _finish();
  }

  void _finish() {
    if (_disposed) return;
    _stopTimer();
    // Use the live stopwatch reading, not the last 32ms tick snapshot.
    _elapsed = _stopwatch.elapsed;
    final Duration? previousBest = best;
    _lastRecord = _elapsed;
    _records.add(_elapsed);
    _bestTime = previousBest == null || _elapsed < previousBest;
    _setPhase(SessionPhase.finished);
  }

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch.stop();
    _elapsed = _stopwatch.elapsed;
  }

  void _setPhase(SessionPhase phase) {
    if (_disposed || _phase == phase) return;
    _phase = phase;
    notifyListeners();
  }

  Duration? _averageOf(int count) {
    if (_records.length < count) return null;
    final List<Duration> window =
        _records.sublist(_records.length - count).toList()
          ..sort((Duration a, Duration b) => a.compareTo(b));
    final Iterable<Duration> middle = window.sublist(1, count - 1);
    final int total = middle.fold<int>(
      0,
      (int sum, Duration item) => sum + item.inMicroseconds,
    );
    return Duration(microseconds: total ~/ (count - 2));
  }
}

String formatDuration(Duration duration) {
  final int minutes = duration.inMinutes;
  final int seconds = duration.inSeconds % 60;
  final int centiseconds = (duration.inMilliseconds % 1000) ~/ 10;
  final String tail =
      '${seconds.toString().padLeft(2, '0')}'
      '.${centiseconds.toString().padLeft(2, '0')}';
  return '$minutes:$tail';
}

String formatDurationOrDash(Duration? duration) =>
    duration == null ? '-' : formatDuration(duration);
