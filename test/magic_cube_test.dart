import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('几何运算', () {
    test('90° 旋转矩阵精确无误差', () {
      final Mat3 turn = Mat3.quarterTurn(CubeAxis.y, 1);
      expect(turn.transform(const Vec3(0, 0, 1)), const Vec3(1, 0, 0));
      expect(turn.transform(const Vec3(1, 0, 0)), const Vec3(0, 0, -1));
    });

    test('同一方向转动四次回到原状', () {
      Mat3 rotation = Mat3.identity;
      for (int i = 0; i < 4; i++) {
        rotation = Mat3.quarterTurn(CubeAxis.z, 1).multiply(rotation);
      }
      expect(rotation.transform(const Vec3(1, 0, 0)), const Vec3(1, 0, 0));
      expect(rotation.transform(const Vec3(0, 1, 0)), const Vec3(0, 1, 0));
    });

    test('向量叉积遵循右手定则', () {
      expect(
        const Vec3(0, 0, 1).cross(const Vec3(1, 0, 0)),
        const Vec3(0, 1, 0),
      );
    });
  });

  group('魔方状态', () {
    test('初始状态已复原，共 27 块 54 张贴纸', () {
      final CubeState state = CubeState();
      expect(state.cubies.length, 27);
      expect(
        state.cubies.fold<int>(
          0,
          (int sum, Cubie cubie) =>
              sum + cubie.stickers.where((int? s) => s != null).length,
        ),
        54,
      );
      expect(state.isSolved, isTrue);
      expect(state.solvedFaceCount, 6);
    });

    test('单次转动后不再复原，但右面与左面仍然完整', () {
      final CubeState state = CubeState()..applyMove(CubeMove.parse('R'));
      expect(state.isSolved, isFalse);
      expect(state.solvedFaceCount, 2);
    });

    test('同一面转动四次回到原状', () {
      final CubeState state = CubeState();
      for (int i = 0; i < 4; i++) {
        state.applyMove(CubeMove.parse('R'));
      }
      expect(state.isSolved, isTrue);
    });

    test('(R U R\' U\') 重复六次回到原状', () {
      final CubeState state = CubeState();
      final List<CubeMove> sexy = CubeMove.parseSequence("R U R' U'");
      for (int i = 0; i < 6; i++) {
        state.applyMoves(sexy);
      }
      expect(state.isSolved, isTrue);
    });

    test('打乱后逆序执行逆转动可以复原', () {
      final CubeState state = CubeState();
      final List<CubeMove> scramble = CubeMove.randomScramble(
        length: 40,
        random: _random(7),
      );
      state.applyMoves(scramble);
      expect(state.isSolved, isFalse);
      for (final CubeMove move in scramble.reversed) {
        state.applyMove(move.inverse);
      }
      expect(state.isSolved, isTrue);
    });

    test('中层转动只影响中层方块', () {
      final CubeState state = CubeState();
      final List<Vec3> corners = <Vec3>[
        for (final Cubie cubie in state.cubies)
          if (cubie.position.x.abs() == 1 &&
              cubie.position.y.abs() == 1 &&
              cubie.position.z.abs() == 1)
            cubie.position,
      ];
      state.applyMove(CubeMove.parse('M'));
      for (final Vec3 corner in corners) {
        expect(state.cubieAt(corner), isNotNull, reason: '角块不应移动: $corner');
      }
    });
  });

  group('转动记号', () {
    test('常见记号解析与输出一致', () {
      for (final String token in <String>[
        'R',
        "R'",
        'R2',
        'L',
        'U',
        "U'",
        'D',
        'F',
        'B',
        'M',
        'E',
        'S',
        'x',
        'y',
        'z',
      ]) {
        expect(CubeMove.parse(token).notation(), token, reason: token);
      }
    });

    test('非法记号抛出异常', () {
      expect(() => CubeMove.parse('Q'), throwsA(isA<FormatException>()));
    });

    test('序列解析', () {
      final List<CubeMove> moves = CubeMove.parseSequence("R U R' U'");
      expect(moves.length, 4);
      expect(moves.map((CubeMove m) => m.notation()).join(' '), "R U R' U'");
    });

    test('打乱不会连续转动同一个面', () {
      final List<CubeMove> moves = CubeMove.randomScramble(
        length: 60,
        random: _random(3),
      );
      expect(moves.length, 60);
      for (int i = 1; i < moves.length; i++) {
        expect(moves[i] == moves[i - 1], isFalse);
      }
    });

    test('记号与层索引一致', () {
      final CubeMove right = CubeMove.parse('R');
      expect(right.axis, CubeAxis.x);
      expect(right.layer, 2);
      expect(right.quarterTurns, -1);
      final CubeMove left = CubeMove.parse('L');
      expect(left.layer, 0);
      expect(left.quarterTurns, 1);
    });
  });

  group('控制器', () {
    test('无动画环境下立即生效', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      expect(controller.isSolved, isTrue);
      await controller.applyNotation("R U R' U'");
      expect(controller.isSolved, isFalse);
      expect(controller.moveCount, 4);
      await controller.undoAll();
      expect(controller.isSolved, isTrue);
      expect(controller.moveCount, 0);
    });

    test('撤销与重置', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      await controller.applyMove(CubeMove.parse('R'));
      expect(controller.isSolved, isFalse);
      await controller.undo();
      expect(controller.isSolved, isTrue);
      await controller.scramble(length: 10, random: _random(11));
      expect(controller.isSolved, isFalse);
      controller.reset();
      expect(controller.isSolved, isTrue);
      expect(controller.history, isEmpty);
    });

    test('整体转动不改变复原状态', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      await controller.applyMove(CubeMove.parse('x'));
      await controller.applyMove(CubeMove.parse('y'));
      expect(controller.state.isSolved, isTrue);
    });
  });

  group('渲染层级', () {
    /// Layer order must be far-to-near, or turning and resting layers
    /// intersect.
    List<double> layerSequence(CubeScene scene) => <double>[
      for (final SceneFace face in scene.drawOrder)
        scene.cubies[face.cubieIndex].position.y,
    ];

    bool nonDecreasing(List<double> values) {
      for (int i = 1; i < values.length; i++) {
        if (values[i] < values[i - 1] - 1e-6) return false;
      }
      return true;
    }

    bool nonIncreasing(List<double> values) {
      for (int i = 1; i < values.length; i++) {
        if (values[i] > values[i - 1] + 1e-6) return false;
      }
      return true;
    }

    test('中层转动时按层由远及近绘制（相机在上方）', () {
      final CubeScene scene = CubeScene(
        state: CubeState(),
        turn: const CubeTurn(axis: CubeAxis.y, layer: 1, angle: 0.8),
        yaw: MagicCubeController.defaultYaw,
        pitch: MagicCubeController.defaultPitch,
        viewport: const Size(400, 400),
      );
      expect(nonDecreasing(layerSequence(scene)), isTrue);
    });

    test('顶层转动时按层由远及近绘制（相机在上方）', () {
      final CubeScene scene = CubeScene(
        state: CubeState(),
        turn: const CubeTurn(axis: CubeAxis.y, layer: 2, angle: -0.7),
        yaw: MagicCubeController.defaultYaw,
        pitch: MagicCubeController.defaultPitch,
        viewport: const Size(400, 400),
      );
      expect(nonDecreasing(layerSequence(scene)), isTrue);
    });

    test('相机在下方时绘制顺序反向', () {
      final CubeScene scene = CubeScene(
        state: CubeState(),
        turn: const CubeTurn(axis: CubeAxis.y, layer: 1, angle: 0.8),
        yaw: MagicCubeController.defaultYaw,
        pitch: -0.5,
        viewport: const Size(400, 400),
      );
      expect(nonIncreasing(layerSequence(scene)), isTrue);
    });

    test('最外层 8 个角会生成圆角补丁', () {
      final CubeScene scene = CubeScene(
        state: CubeState(),
        yaw: MagicCubeController.defaultYaw,
        pitch: MagicCubeController.defaultPitch,
        viewport: const Size(400, 400),
      );
      final List<SceneFace> patches = scene.drawOrder
          .where((SceneFace face) => face.isCornerPatch)
          .toList();
      expect(patches.length, greaterThanOrEqualTo(2));
      expect(patches.first.corners.length, greaterThan(4));
      expect(
        patches.first.corners.every(
          (Offset p) => p.dx.isFinite && p.dy.isFinite,
        ),
        isTrue,
      );
    });

    test('只有角块的面才会被标记为外角', () {
      final CubeScene scene = CubeScene(
        state: CubeState(),
        yaw: 0.78,
        pitch: 0.62,
        viewport: const Size(400, 400),
      );
      int marked = 0;
      for (final SceneFace face in scene.drawOrder) {
        if (face.isCornerPatch || face.exteriorCornerMask == 0) continue;
        marked++;
        final Vec3 position = scene.cubies[face.cubieIndex].position;
        expect(
          position.x.abs() + position.y.abs() + position.z.abs(),
          3,
          reason: '只有角块才可能出现外角',
        );
      }
      expect(marked, greaterThan(0));
    });

    test('绕 x 轴转动时按 x 分层排序', () {
      final CubeScene scene = CubeScene(
        state: CubeState(),
        turn: const CubeTurn(axis: CubeAxis.x, layer: 2, angle: 0.6),
        yaw: MagicCubeController.defaultYaw,
        pitch: MagicCubeController.defaultPitch,
        viewport: const Size(400, 400),
      );
      final List<double> sequence = <double>[
        for (final SceneFace face in scene.drawOrder)
          scene.cubies[face.cubieIndex].position.x,
      ];
      expect(sequence.last, closeTo(1, 1e-6));
    });
  });

  group('视角', () {
    /// View matrices must stay orthogonal, or dragging stretches the image.
    void expectOrthogonal(Mat3 view) {
      final Mat3 product = view.transpose.multiply(view);
      for (int i = 0; i < 9; i++) {
        expect(
          product[i],
          closeTo(Mat3.identity[i], 1e-9),
          reason: '视角矩阵应保持正交（元素 $i）',
        );
      }
    }

    test('俯仰角不再被限制', () {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      controller.setViewAngles(pitch: 3.0);
      expect(controller.pitch, closeTo(3.0, 1e-6));
      expectOrthogonal(controller.viewRotation);
    });

    test('竖直拖拽可以一直翻过顶 / 底', () {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);

      // A pole flip shows up as a sign change in the view-space y of
      // world up.
      double previous = controller.viewRotation
          .transform(const Vec3(0, 1, 0))
          .y;
      bool flipped = false;
      for (int i = 0; i < 80; i++) {
        controller.orbitBy(dy: 0.1);
        final double current = controller.viewRotation
            .transform(const Vec3(0, 1, 0))
            .y;
        if (current * previous < 0) flipped = true;
        previous = current;
        expectOrthogonal(controller.viewRotation);
      }
      expect(flipped, isTrue, reason: '总共转了 8 弧度，必然翻过顶或底');
    });

    test('翻过顶之后水平拖拽仍然是绕屏幕竖直轴', () {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);

      for (int i = 0; i < 20; i++) {
        controller.orbitBy(dy: 0.15);
      }
      final Mat3 before = controller.viewRotation;
      controller.orbitBy(dx: 0.3);
      final Mat3 after = controller.viewRotation;

      // A horizontal orbit should only left-multiply a y rotation.
      final Mat3 restored = Mat3.rotationY(-0.3)
          .multiply(after)
          .multiply(before.transpose);
      expectOrthogonal(restored);
      for (int i = 0; i < 9; i++) {
        expect(restored[i], closeTo(Mat3.identity[i], 1e-9), reason: '元素 $i');
      }
    });

    test('视角动画走最短路径且能停在任意姿态', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      controller.setViewAngles(yaw: 0, pitch: 3.0);
      await controller.animateViewTo(yaw: 0.5, pitch: -2.8);
      expect(controller.viewRotation, isNotNull);
      expectOrthogonal(controller.viewRotation);
    });
  });

  group('组件交互', () {
    testWidgets('渲染魔方并命中中心贴纸', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));

      final CubeScene scene = _scene(controller);
      final SceneFace face = _largestSticker(scene);
      final Offset target = _centroid(face);
      expect(scene.pick(target), isNotNull);
      expect(scene.pick(const Offset(4, 4)), isNull);
    });

    testWidgets('在贴纸上拖拽可以拧动一层', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));

      final Offset local = _centroid(_largestSticker(_scene(controller)));
      final Offset target = local + tester.getTopLeft(find.byType(MagicCube));
      await tester.dragFrom(target, const Offset(70, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(controller.turn, isNull);
      expect(controller.isSolved, isFalse);
      expect(controller.moveCount, 1);
      controller.dispose();
    });

    testWidgets('在魔方之外拖拽只旋转整体视角', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      final double yaw = controller.yaw;

      final Offset outside =
          tester.getTopLeft(find.byType(MagicCube)) + const Offset(6, 6);
      await tester.dragFrom(outside, const Offset(60, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(controller.yaw, isNot(yaw));
      expect(controller.state.isSolved, isTrue);
      expect(controller.moveCount, 0);
      controller.dispose();
    });

    testWidgets('第二根手指按下后转为旋转视角，正在进行的拧层会回滚', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      final Offset center = tester.getCenter(find.byType(MagicCube));

      final TestGesture first = await tester.createGesture();
      final TestGesture second = await tester.createGesture();
      await first.down(center + const Offset(-60, -40));
      await first.moveTo(center + const Offset(-40, -40));
      await tester.pump();
      expect(controller.turn, isNotNull, reason: '单指应当先进入拧层');

      await second.down(center + const Offset(60, 40));
      await second.moveTo(center + const Offset(80, 40));
      // The rollback is animated; advance frames until it settles.
      for (int i = 0; i < 8 && controller.turn != null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.turn, isNull, reason: '拧层应当被回滚');
      expect(controller.moveCount, 0, reason: '回滚不算一步');

      final double yaw = controller.yaw;
      await first.moveTo(center + const Offset(20, -40));
      await second.moveTo(center + const Offset(140, 40));
      await tester.pump();
      expect(controller.yaw, isNot(yaw));
      expect(controller.turn, isNull);

      await first.up();
      await second.up();
      await tester.pump(const Duration(seconds: 1));
      expect(controller.moveCount, 0);
      controller.dispose();
    });

    testWidgets('在空白处竖直拖拽可以翻过顶部', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));

      final Offset outside =
          tester.getTopLeft(find.byType(MagicCube)) + const Offset(6, 380);
      await tester.dragFrom(outside, const Offset(0, -340));
      await tester.pump();

      // The old Euler-angle implementation clamped pitch to +/-83 degrees.
      expect(controller.pitch.abs(), greaterThan(math.pi / 2));
      controller.dispose();
    });

    testWidgets('松手后的惯性同方向继续且不会失控', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      final Offset start =
          tester.getTopLeft(find.byType(MagicCube)) + const Offset(6, 6);
      final double before = controller.yaw;

      await tester.flingFrom(start, const Offset(120, 0), 800);
      await tester.pump();
      final double afterDrag = controller.yaw;
      expect(afterDrag, greaterThan(before));

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      final double settled = controller.yaw;
      expect(settled, greaterThanOrEqualTo(afterDrag));
      expect(settled - afterDrag, lessThan(2.0));
      controller.dispose();
    });

    testWidgets('贴片厚度与阴影参数会改变绘制结果', (WidgetTester tester) async {
      // Compare picture command size instead of GPU snapshots: it does
      // not depend on the test renderer's toImage support.
      int paintCost(CubeTheme theme) {
        final CubeScene scene = CubeScene(
          state: CubeState(),
          yaw: MagicCubeController.defaultYaw,
          pitch: MagicCubeController.defaultPitch,
          viewport: const ui.Size(200, 200),
          gap: theme.gap,
          cornerRadius: theme.outerCornerRadius,
        );
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final ui.Canvas canvas = ui.Canvas(recorder);
        CubePainter(
          scene: scene,
          theme: theme,
        ).paint(canvas, const ui.Size(200, 200));
        final ui.Picture picture = recorder.endRecording();
        final int bytes = picture.approximateBytesUsed;
        picture.dispose();
        return bytes;
      }

      expect(const CubeTheme.flat().stickerThickness, 0);
      expect(const CubeTheme.flat().stickerShadowOpacity, 0);

      final int flat = paintCost(const CubeTheme.flat());
      final int tiled = paintCost(
        const CubeTheme(stickerThickness: 0.08, stickerShadowOpacity: 0.5),
      );
      expect(flat, greaterThan(0));
      expect(tiled, isNot(flat));

      final int atLimit = paintCost(
        const CubeTheme(stickerThickness: CubeTheme.maxStickerThickness),
      );
      final int beyondLimit = paintCost(const CubeTheme(stickerThickness: 5));
      expect(beyondLimit, atLimit);

      final int offsetAtLimit = paintCost(
        const CubeTheme(stickerShadowOffset: CubeTheme.maxStickerShadowOffset),
      );
      final int offsetBeyond = paintCost(
        const CubeTheme(stickerShadowOffset: 9),
      );
      expect(offsetBeyond, offsetAtLimit);
    });

    testWidgets('编程转动会播放动画', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));

      final Future<void> pending = controller.applyMove(CubeMove.parse('R'));
      await tester.pump();
      expect(controller.turn, isNotNull);
      expect(controller.isAnimating, isTrue);

      await tester.pump(const Duration(milliseconds: 500));
      await pending;

      expect(controller.turn, isNull);
      expect(controller.state.isSolved, isFalse);
      controller.dispose();
    });
  });
}

Widget _app(MagicCubeController controller) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: MagicCube(controller: controller),
        ),
      ),
    ),
  );
}

CubeScene _scene(MagicCubeController controller) => CubeScene(
  state: controller.state,
  yaw: controller.yaw,
  pitch: controller.pitch,
  viewport: const Size(400, 400),
  gap: const CubeTheme().gap,
);

SceneFace _largestSticker(CubeScene scene) {
  SceneFace best = scene.drawOrder.firstWhere(
    (SceneFace face) => face.sticker != null,
  );
  double bestArea = 0;
  for (final SceneFace face in scene.drawOrder) {
    if (face.sticker == null) continue;
    final double area = _area(face.corners);
    if (area > bestArea) {
      bestArea = area;
      best = face;
    }
  }
  return best;
}

Offset _centroid(SceneFace face) {
  double x = 0;
  double y = 0;
  for (final Offset corner in face.corners) {
    x += corner.dx;
    y += corner.dy;
  }
  return Offset(x / face.corners.length, y / face.corners.length);
}

double _area(List<Offset> points) {
  double sum = 0;
  for (int i = 0; i < points.length; i++) {
    final Offset a = points[i];
    final Offset b = points[(i + 1) % points.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

math.Random _random(int seed) => math.Random(seed);
