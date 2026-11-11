import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:magic_cube_example/session.dart';

void main() {
  test('打乱结束后进入计时阶段', () async {
    final MagicCubeController controller = MagicCubeController();
    final CubeSession session = CubeSession(controller);
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    await session.start(length: 6);
    expect(session.phase, SessionPhase.solving);
    expect(controller.isSolved, isFalse);
    expect(session.records, isEmpty);
  });

  test('打乱过程中释放会话不会抛错，也不会遗留定时器', () async {
    final MagicCubeController controller = MagicCubeController();
    final CubeSession session = CubeSession(controller);
    addTearDown(controller.dispose);

    final Future<void> starting = session.start(length: 20);
    session.dispose();
    await starting;

    // After dispose, start() must not notify a disposed notifier or leave
    // a pending timer.
    expect(session.phase, SessionPhase.scrambling);
  });

  test('500ms 内复原不会丢成绩，门槛过后由计时器补判', () async {
    final MagicCubeController controller = MagicCubeController();
    final CubeSession session = CubeSession(controller);
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    await session.start(length: 2);
    expect(session.phase, SessionPhase.solving);
    final List<CubeMove> undoMoves = <CubeMove>[
      for (final CubeMove move in controller.history.reversed) move.inverse,
    ];
    await controller.applyMoves(undoMoves);
    expect(controller.isSolved, isTrue);
    // Within the guard, the solve is deferred rather than dropped.
    expect(session.phase, SessionPhase.solving);
    // Stopwatch uses real time; fake-async pump cannot advance it.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(session.phase, SessionPhase.finished);
    expect(session.records.length, 1);
  });

  test('格式化与统计的默认值', () {
    final MagicCubeController controller = MagicCubeController();
    final CubeSession session = CubeSession(controller);
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    expect(
      formatDuration(const Duration(seconds: 75, milliseconds: 340)),
      '1:15.34',
    );
    expect(formatDurationOrDash(null), '-');
    expect(session.totalSolves, 0);
    expect(session.best, isNull);
    expect(session.worst, isNull);
    expect(session.averageOf5, isNull);
    expect(session.averageOf12, isNull);
    expect(session.phase, SessionPhase.idle);
  });
}
