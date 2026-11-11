import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(MagicCubeController controller) => MaterialApp(
  home: Scaffold(
    body: Center(child: MagicCube(controller: controller)),
  ),
);

Offset _stickerCenter(
  WidgetTester tester,
  MagicCubeController controller,
  Vec3 position,
) {
  final Size size = tester.getSize(find.byType(MagicCube));
  final CubeScene scene = CubeScene(
    state: controller.state,
    turn: null,
    yaw: controller.yaw,
    pitch: controller.pitch,
    view: controller.viewRotation,
    viewport: size,
  );
  final int index = controller.state.cubies.indexWhere(
    (Cubie c) => c.position == position,
  );
  expect(index, isNot(-1));
  final SceneFace face = scene.drawOrder.firstWhere(
    (SceneFace f) => f.cubieIndex == index && f.sticker != null,
  );
  double x = 0;
  double y = 0;
  for (final Offset p in face.corners) {
    x += p.dx;
    y += p.dy;
  }
  return tester.getTopLeft(find.byType(MagicCube)) +
      Offset(x / face.corners.length, y / face.corners.length);
}

void main() {
  testWidgets('已经停到位时立刻落定，不再空等一个动画周期', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    controller.beginTurn(axis: CubeAxis.y, layer: 2);
    controller.updateTurn(math.pi / 2);
    await tester.pump();
    expect(controller.turn, isNotNull);

    bool settled = false;
    unawaited(controller.endTurn().then((void _) => settled = true));
    await tester.pump();
    await tester.pump();
    // An identical start/end used to wait the full 220ms tween.
    expect(settled, isTrue, reason: '已经到位却还在播放补间');
    expect(controller.turn, isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('序列中的每一步都会补间，而不是只放第一段', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    unawaited(
      controller.applyNotation(
        "R U R U",
        duration: const Duration(milliseconds: 200),
      ),
    );
    int frames = 0;
    for (int i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (controller.turn != null) frames++;
    }
    // 4 steps x 200ms / 16ms ~= 50 frames; instantly skipped steps
    // leave only ~15.
    expect(
      frames,
      greaterThanOrEqualTo(35),
      reason: '过渡帧只有 $frames 帧，多步里有几步被瞬间跳过',
    );
    expect(controller.moveCount, 4);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('松手时的甩动速度会被补间接住', (WidgetTester tester) async {
    Future<double> advanceAfterRelease(double angularVelocity) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      await tester.pump();

      controller.beginTurn(axis: CubeAxis.y, layer: 2);
      controller.updateTurn(0.78);
      await tester.pump();
      final double before = controller.turn!.angle;

      unawaited(controller.endTurn(angularVelocity: angularVelocity));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      final double after = controller.turn?.angle ?? double.nan;

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      return (after - before).abs();
    }

    final double withoutVelocity = await advanceAfterRelease(0);
    final double withVelocity = await advanceAfterRelease(-8.0);
    expect(
      withVelocity,
      greaterThan(withoutVelocity * 2),
      reason: '初速度没有被接住：无甩动=$withoutVelocity，有甩动=$withVelocity',
    );
  });

  testWidgets('第二根手指按下时，那一层是补间收回而不是瞬间弹回', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    final Offset sticker = _stickerCenter(
      tester,
      controller,
      const Vec3(1, 1, 1),
    );

    final TestGesture first = await tester.createGesture();
    final TestGesture second = await tester.createGesture();
    await first.down(sticker);
    for (int i = 0; i < 8; i++) {
      await first.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    final double before = controller.turn?.angle ?? 0;
    expect(before.abs(), greaterThan(0.2), reason: '拖拽应当转出一个可观的角度');

    await second.down(
      tester.getCenter(find.byType(MagicCube)) + const Offset(60, 40),
    );
    await tester.pump();

    final List<double> intermediates = <double>[];
    for (int frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final double? angle = controller.turn?.angle;
      if (angle == null) break;
      final bool strictlyBetween =
          angle.abs() > 1e-3 && angle.abs() < before.abs() - 1e-3;
      if (strictlyBetween) intermediates.add(angle);
    }

    expect(
      intermediates.length,
      greaterThanOrEqualTo(3),
      reason: '应为回滚播放若干过渡帧，实际只有 $intermediates',
    );
    for (int i = 1; i < intermediates.length; i++) {
      expect(
        intermediates[i].abs(),
        lessThan(intermediates[i - 1].abs()),
        reason: '回滚过程有回抖：$intermediates',
      );
    }
    expect(controller.isSolved, isTrue, reason: '回滚之后不应写入任何转动');
    expect(controller.moveCount, 0);

    await first.up();
    await second.up();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('手势被取消时同样补间收回', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    final Offset sticker = _stickerCenter(
      tester,
      controller,
      const Vec3(1, 1, 1),
    );

    final TestGesture gesture = await tester.startGesture(sticker);
    for (int i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    final double before = controller.turn?.angle ?? 0;
    expect(before.abs(), greaterThan(0.2));

    await gesture.cancel();
    await tester.pump();

    final List<double> intermediates = <double>[];
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final double? angle = controller.turn?.angle;
      if (angle == null) break;
      if (angle.abs() > 1e-3 && angle.abs() < before.abs() - 1e-3) {
        intermediates.add(angle);
      }
    }
    expect(
      intermediates.length,
      greaterThanOrEqualTo(3),
      reason: '取消手势应当有过渡，实际 $intermediates',
    );
    expect(controller.moveCount, 0);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('吸附角保留方向与圈数，归一化 quarter 只用来提交 move', () {
    CubeTurn turn(double angle) =>
        CubeTurn(axis: CubeAxis.y, layer: 1, angle: angle);

    expect(turn(-math.pi).nearestQuarterTurns, -2);
    expect(turn(-math.pi).nearestRightAngle, closeTo(-math.pi, 1e-12));
    expect(turn(-math.pi * 1.5).nearestQuarterTurns, -3);
    expect(turn(math.pi * 1.5).nearestQuarterTurns, 3);
    expect(turn(math.pi * 2).nearestQuarterTurns, 4);
    expect(turn(double.nan).nearestQuarterTurns, 0);
    expect(turn(double.infinity).nearestQuarterTurns, 0);
    // Equivalence for committing a move: -180 deg and +180 deg are the same.
    expect(turn(-math.pi).snappedQuarterTurns, 2);
  });

  testWidgets('负向半圈已到位，松手不再重播一整圈', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    controller.beginTurn(axis: CubeAxis.y, layer: 1);
    controller.updateTurn(-math.pi);
    await tester.pump();

    final List<double> angles = <double>[];
    void record() {
      final double? angle = controller.turn?.angle;
      if (angle != null) angles.add(angle);
    }

    controller.addListener(record);
    final Future<void> settled = controller.endTurn();
    await tester.pump();
    int settleFrames = 0;
    for (int i = 0; i < 30 && controller.turn != null; i++) {
      settleFrames++;
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settled;

    expect(settleFrames, lessThanOrEqualTo(1), reason: '手指已经停在 -180 度，却还在播放补间');
    expect(
      angles.every((double a) => (a + math.pi).abs() < 0.05),
      isTrue,
      reason: '松手后角度扫过了整整一圈：$angles',
    );
    expect(controller.turn, isNull);
    expect(controller.moveCount, 1);
    expect(
      controller.history.single,
      const CubeMove(axis: CubeAxis.y, layer: 1, quarterTurns: 2),
    );

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('负向多圈的手势同样吸附到最近的直角', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    controller.beginTurn(axis: CubeAxis.y, layer: 1);
    controller.updateTurn(-math.pi * 1.5);
    await tester.pump();

    final List<double> angles = <double>[];
    void record() {
      final double? angle = controller.turn?.angle;
      if (angle != null) angles.add(angle);
    }

    controller.addListener(record);
    final Future<void> settled = controller.endTurn();
    await tester.pump();
    for (int i = 0; i < 30 && controller.turn != null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settled;

    expect(
      angles.every((double a) => (a + math.pi * 1.5).abs() < 0.05),
      isTrue,
      reason: '松手后角度绕回了正方向：$angles',
    );
    expect(controller.moveCount, 1);
    expect(
      controller.history.single,
      const CubeMove(axis: CubeAxis.y, layer: 1, quarterTurns: 1),
    );

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('差一点到位时只补足剩余角度，不翻到另一侧直角', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    const double released = -math.pi + 0.2;
    controller.beginTurn(axis: CubeAxis.y, layer: 1);
    controller.updateTurn(released);
    await tester.pump();

    final List<double> angles = <double>[];
    void record() {
      final double? angle = controller.turn?.angle;
      if (angle != null) angles.add(angle);
    }

    controller.addListener(record);
    final Future<void> settled = controller.endTurn();
    await tester.pump();
    for (int i = 0; i < 30 && controller.turn != null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settled;

    expect(angles, isNotEmpty, reason: '这一点残差应当有补间');
    expect(
      angles.every((double a) => a < -math.pi + 0.21),
      isTrue,
      reason: '补间越过了 -180 度，转到了别的直角：$angles',
    );
    expect(angles.last, closeTo(-math.pi, 1e-6));
    expect(
      controller.history.single,
      const CubeMove(axis: CubeAxis.y, layer: 1, quarterTurns: 2),
    );

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('拖过整圈只补足残差，不倒放一圈也不写历史', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    await tester.pumpWidget(_app(controller));
    await tester.pump();

    const double released = math.pi * 2 - 0.1;
    controller.beginTurn(axis: CubeAxis.y, layer: 1);
    controller.updateTurn(released);
    await tester.pump();

    final List<double> angles = <double>[];
    void record() {
      final double? angle = controller.turn?.angle;
      if (angle != null) angles.add(angle);
    }

    controller.addListener(record);
    final Future<void> settled = controller.endTurn();
    await tester.pump();
    for (int i = 0; i < 30 && controller.turn != null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settled;

    expect(
      angles.every((double a) => a > released - 0.01),
      isTrue,
      reason: '整圈被倒放回 0 度：$angles',
    );
    expect(angles.last, closeTo(math.pi * 2, 1e-6));
    expect(controller.moveCount, 0, reason: '转满一圈不应写进历史');

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
