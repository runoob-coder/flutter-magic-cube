import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('N 阶记号', () {
    test('面记号映射到真正的最外层', () {
      expect(CubeMove.parse('R', size: 5).layer, 4);
      expect(CubeMove.parse('L', size: 5).layer, 0);
      expect(CubeMove.parse('U', size: 7).layer, 6);
      expect(CubeMove.parse('D', size: 7).layer, 0);
      expect(CubeMove.parse('M', size: 5).layer, 2);
      expect(CubeMove.parse('R', size: 3).layer, 2);
    });

    test('notation 与 parse 在同一 size 下可逆（含内层记号）', () {
      for (final int size in <int>[3, 5, 7]) {
        for (final CubeAxis axis in CubeAxis.values) {
          for (int layer = 0; layer < size; layer++) {
            for (int turns = -2; turns <= 2; turns++) {
              if (turns == 0) continue;
              final CubeMove move = CubeMove(
                axis: axis,
                layer: layer,
                quarterTurns: turns,
              );
              final String token = move.notation(size: size);
              expect(token.startsWith('?'), isFalse, reason: '$size/$token');
              expect(
                CubeMove.parse(token, size: size),
                move,
                reason: '$size/$turns -> $token',
              );
            }
          }
        }
        for (int turns = -2; turns <= 2; turns++) {
          if (turns == 0) continue;
          final CubeMove whole = CubeMove(
            axis: CubeAxis.y,
            layer: 0,
            quarterTurns: turns,
            wholeCube: true,
          );
          expect(CubeMove.parse(whole.notation(size: size), size: size), whole);
        }
      }
    });

    test('内层记号与整体转动互不混淆', () {
      final CubeMove slice = CubeMove.parse("3X'", size: 5);
      expect(slice.axis, CubeAxis.x);
      expect(slice.layer, 3);
      expect(slice.wholeCube, isFalse);
      expect(slice.quarterTurns, -1);
      expect(CubeMove.parse('x').wholeCube, isTrue);
    });

    test('非法后缀、层号与阶数显式报错', () {
      for (final String token in <String>[
        'R5',
        'R0',
        'R4',
        'R9',
        'Q',
        'Rw',
        'R#3',
      ]) {
        expect(
          () => CubeMove.parse(token),
          throwsFormatException,
          reason: token,
        );
      }
      expect(() => CubeMove.parse('9X', size: 5), throwsFormatException);
      expect(() => CubeMove.parse('R', size: 4), throwsArgumentError);
      expect(() => CubeMove.parse('R', size: 13), throwsArgumentError);
      expect(() => CubeMove.parseSequence('R R5'), throwsFormatException);
    });

    test('打乱按 size 生成最外层的层索引', () {
      final List<CubeMove> moves = CubeMove.randomScramble(
        length: 20,
        size: 5,
        random: math.Random(7),
      );
      expect(moves.length, 20);
      expect(moves.every((CubeMove m) => m.layer == 0 || m.layer == 4), isTrue);
      expect(() => CubeMove.randomScramble(length: -1), throwsArgumentError);
    });

    test('控制器的 applyNotation / scramble 透传当前阶数', () async {
      final MagicCubeController controller = MagicCubeController(size: 5);
      addTearDown(controller.dispose);
      await controller.applyNotation('R U');
      expect(controller.history.map((CubeMove m) => m.layer), <int>[4, 4]);
      await controller.scramble(length: 4, random: math.Random(3));
      expect(
        controller.history.every((CubeMove m) => m.layer == 0 || m.layer == 4),
        isTrue,
      );
      for (final CubeMove move in controller.history) {
        expect(CubeMove.parse(move.notation(size: 5), size: 5), move);
      }
    });
  });

  group('核心状态与数学', () {
    test('cubies 只读，损坏的贴纸不会被判成复原', () {
      final CubeState state = CubeState();
      expect(() => state.cubies.clear(), throwsUnsupportedError);
      final Cubie cubie = state.cubies.firstWhere(
        (Cubie c) => c.stickers.any((int? s) => s != null),
      );
      final int face = cubie.stickers.indexWhere((int? s) => s != null);
      cubie.stickers[face] = null;
      expect(state.isSolved, isFalse);
      expect(state.solvedFaceCount, 5);
    });

    test('阶数上限、层索引、坐标都做运行时校验', () {
      expect(() => CubeState(size: 1), throwsArgumentError);
      expect(() => CubeState(size: 4), throwsArgumentError);
      expect(() => CubeState(size: 13), throwsArgumentError);
      expect(CubeState(size: 7).cubies.length, 343);
      final CubeState state = CubeState();
      expect(
        () => state.applyMove(
          const CubeMove(axis: CubeAxis.x, layer: 99, quarterTurns: 1),
        ),
        throwsRangeError,
      );
      expect(() => state.layerOfCoordinate(double.nan), throwsArgumentError);
      expect(state.layerOfCoordinate(1), 2);
    });

    test('copy 沿用 revision，isFaceSolved 与 solvedFaceCount 一致', () {
      final CubeState state = CubeState()..applyMove(CubeMove.parse('R'));
      expect(state.copy().revision, state.revision);
      expect(state.solvedFaceCount, 2);
      expect(state.isSolved, isFalse);
      expect(
        kFaceNormals.where(state.isFaceSolved).length,
        state.solvedFaceCount,
      );
    });

    test('Mat3 校验长度与有限性，并实现值相等', () {
      expect(() => Mat3(<double>[1, 0, 0]), throwsArgumentError);
      expect(
        () => Mat3(<double>[1, 0, 0, 0, 1, 0, 0, 0, double.nan]),
        throwsArgumentError,
      );
      expect(Mat3(<double>[1, 0, 0, 0, 1, 0, 0, 0, 1]), Mat3.identity);
      expect(
        Mat3(<double>[1, 0, 0, 0, 1, 0, 0, 0, 1]).hashCode,
        Mat3.identity.hashCode,
      );
      expect(Mat3.axisAngleOf(Mat3.identity).$1, const Vec3.zero());
      expect(Mat3.rotationAround(const Vec3.zero(), 1), Mat3.identity);
      expect(Mat3.quarterTurn(CubeAxis.y, 5), Mat3.quarterTurn(CubeAxis.y, 1));
    });

    test('isAxisAligned 不再把非轴向量误判为轴对齐', () {
      expect(const Vec3(1, 0, 0).isAxisAligned, isTrue);
      expect(const Vec3(0, -1, 0).isAxisAligned, isTrue);
      expect(const Vec3.zero().isAxisAligned, isTrue);
      expect(const Vec3(0.5, 0.5, 0).isAxisAligned, isFalse);
      expect(const Vec3(0.3, 0.3, 0.4).isAxisAligned, isFalse);
      expect(const Vec3(2, -1, 0).isAxisAligned, isFalse);
    });

    test('Cubie 构造与面索引校验', () {
      expect(
        () => Cubie(position: const Vec3.zero(), stickers: <int?>[1, 2, 3]),
        throwsArgumentError,
      );
      final Cubie cubie = Cubie(position: const Vec3.zero());
      expect(() => cubie.worldNormalOf(6), throwsRangeError);
      expect(() => cubie.worldNormalOf(-1), throwsRangeError);
    });

    test('CubeTurn 多圈角度按 4 取模，NaN 不炸', () {
      expect(
        const CubeTurn(
          axis: CubeAxis.x,
          layer: 1,
          angle: math.pi * 2,
        ).snappedQuarterTurns,
        0,
      );
      expect(
        const CubeTurn(
          axis: CubeAxis.x,
          layer: 1,
          angle: math.pi * 1.5,
        ).snappedQuarterTurns,
        -1,
      );
      expect(
        const CubeTurn(
          axis: CubeAxis.x,
          layer: 1,
          angle: -math.pi * 2,
        ).snappedQuarterTurns,
        0,
      );
      expect(
        const CubeTurn(
          axis: CubeAxis.x,
          layer: 1,
          angle: double.nan,
        ).snappedQuarterTurns,
        0,
      );
    });

    test('CubeMove 相等性按归一化语义', () {
      expect(
        const CubeMove(axis: CubeAxis.x, layer: 2, quarterTurns: 5),
        const CubeMove(axis: CubeAxis.x, layer: 2, quarterTurns: 1),
      );
      expect(
        const CubeMove(axis: CubeAxis.x, layer: 2, quarterTurns: 5).hashCode,
        const CubeMove(axis: CubeAxis.x, layer: 2, quarterTurns: 1).hashCode,
      );
      expect(
        const CubeMove(
          axis: CubeAxis.x,
          layer: 0,
          quarterTurns: 1,
          wholeCube: true,
        ),
        const CubeMove(
          axis: CubeAxis.x,
          layer: 2,
          quarterTurns: 1,
          wholeCube: true,
        ),
      );
    });
  });

  group('主题', () {
    test('copyWith 能覆盖全部四个光照参数', () {
      const CubeTheme base = CubeTheme();
      final CubeTheme themed = base.copyWith(
        ambient: 0.11,
        diffuse: 0.22,
        stickerAmbient: 0.33,
        stickerDiffuse: 0.44,
      );
      expect(themed.ambient, 0.11);
      expect(themed.diffuse, 0.22);
      expect(themed.stickerAmbient, 0.33);
      expect(themed.stickerDiffuse, 0.44);
      expect(base.ambient, 0.62);
      expect(base.copyWith().ambient, 0.62);
    });

    test('copyWith(centerLogo: null) 能清空继承来的 logo', () async {
      final ui.Image image = await renderFlutterLogoToImage(size: 8);
      addTearDown(image.dispose);
      final CubeTheme withLogo = const CubeTheme().copyWith(centerLogo: image);
      expect(withLogo.centerLogo, same(image));
      expect(withLogo.copyWith(centerLogo: null).centerLogo, isNull);
      expect(withLogo.copyWith(logoScale: 0.5).centerLogo, same(image));
      expect(() => renderTextToImage('x', size: 0), throwsArgumentError);
      expect(
        () => renderFlutterLogoToImage(size: double.nan),
        throwsArgumentError,
      );
    });
  });

  group('控制器状态机', () {
    test('无 vsync 时 cancelTurn 不留幽灵转动', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      controller.beginTurn(axis: CubeAxis.y, layer: 2);
      controller.updateTurn(0.7);
      expect(controller.turn, isNotNull);
      await controller.cancelTurn();
      expect(controller.turn, isNull);
      expect(controller.isIdle, isTrue);
      expect(controller.isSolved, isTrue);
    });

    test('角度为 0 时取消拖拽也会清空转动', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      controller.beginTurn(axis: CubeAxis.y, layer: 2);
      await controller.cancelTurn();
      expect(controller.turn, isNull);
      expect(controller.isIdle, isTrue);
    });

    test('onMoveCommitted 只在真正落定时上报', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      final List<CubeMove> events = <CubeMove>[];
      controller.onMoveCommitted = events.add;
      controller.beginTurn(axis: CubeAxis.y, layer: 2);
      controller.updateTurn(math.pi / 2);
      await controller.endTurn();
      expect(events.length, 1);
      expect(events.single.quarterTurns, 1);
      expect(events.single.axis, CubeAxis.y);
      expect(controller.moveCount, 1);

      await controller.applyMove(CubeMove.parse('R'));
      expect(events.length, 1);
    });

    test('整体转动被打断后仍是整体转动', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      await controller.applyMove(CubeMove.parse('x'));
      expect(controller.history.single.wholeCube, isTrue);
      controller.reset();
      expect(controller.history, isEmpty);
    });

    test('非法输入显式报错，且不计步', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      expect(
        () => controller.beginTurn(axis: CubeAxis.x, layer: 99),
        throwsRangeError,
      );
      controller.beginTurn(axis: CubeAxis.x, layer: 2);
      expect(() => controller.updateTurn(double.nan), throwsArgumentError);
      await controller.cancelTurn();
      await expectLater(controller.applyNotation('R5'), throwsFormatException);
      await expectLater(
        controller.applyMove(
          const CubeMove(axis: CubeAxis.x, layer: 99, quarterTurns: 1),
        ),
        throwsRangeError,
      );
      expect(controller.moveCount, 0);
    });

    test('撤销历史只在逆转动落定后移除，取消会留下可撤销的步', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      await controller.applyMoves(<CubeMove>[
        CubeMove.parse('R'),
        CubeMove.parse('U'),
        CubeMove.parse('F'),
      ]);
      expect(controller.moveCount, 3);
      await controller.undoAll();
      expect(controller.moveCount, 0);
      expect(controller.isSolved, isTrue);

      await controller.applyMoves(<CubeMove>[
        CubeMove.parse('R'),
        CubeMove.parse('U'),
      ]);
      final int epoch = controller.taskEpoch;
      final Future<void> restoring = controller.undoAll();
      controller.stopAnimation();
      await restoring;
      expect(controller.taskEpoch, greaterThan(epoch));
      expect(controller.history, isNotEmpty, reason: '被取消的逆转动仍可再撤销');
    });

    test('applyNotation 的解析错误走 Future 而不是同步抛出', () async {
      final MagicCubeController controller = MagicCubeController();
      addTearDown(controller.dispose);
      await expectLater(controller.applyNotation('Q'), throwsFormatException);
      expect(controller.isIdle, isTrue);
    });
  });

  group('渲染层', () {
    CubeScene scene({
      double yaw = MagicCubeController.defaultYaw,
      double pitch = MagicCubeController.defaultPitch,
      double stickerScale = 0.84,
      double fitRadius = 2.45,
    }) => CubeScene(
      state: CubeState(),
      yaw: yaw,
      pitch: pitch,
      viewport: const Size(400, 400),
      stickerScale: stickerScale,
      fitRadius: fitRadius,
    );

    test('非法相机参数不会产出 NaN 投影', () {
      for (final double bad in <double>[0, -1, double.nan, double.infinity]) {
        final CubeScene s = CubeScene(
          state: CubeState(),
          yaw: MagicCubeController.defaultYaw,
          pitch: MagicCubeController.defaultPitch,
          viewport: const Size(400, 400),
          fitRadius: bad,
          cameraDistance: bad,
          zoom: bad,
        );
        final Offset p = s.projectViewXYZ(0.3, 0.2, 0.1);
        expect(p.dx.isFinite, isTrue, reason: '$bad');
        expect(p.dy.isFinite, isTrue, reason: '$bad');
      }
    });

    test('多个视角下圆角补丁都有限且存在', () {
      for (final (double yaw, double pitch) in <(double, double)>[
        (-0.62, 0.45),
        (0.0, 0.0),
        (0.9, 1.2),
        (-1.4, -0.8),
        (2.7, 0.4),
      ]) {
        final CubeScene s = CubeScene(
          state: CubeState(),
          yaw: yaw,
          pitch: pitch,
          viewport: const Size(400, 400),
        );
        final List<SceneFace> patches = s.drawOrder
            .where((SceneFace f) => f.isCornerPatch)
            .toList();
        expect(patches.length, greaterThanOrEqualTo(2), reason: '$yaw/$pitch');
        expect(
          patches.every(
            (SceneFace f) =>
                f.corners.every((Offset p) => p.dx.isFinite && p.dy.isFinite),
          ),
          isTrue,
          reason: '$yaw/$pitch',
        );
      }
    });

    test('命中测试跟随 stickerScale，缝隙不再被当成贴纸', () {
      final CubeScene big = scene(stickerScale: 1);
      final CubeScene small = scene(stickerScale: 0.3);
      final SceneFace face = big.drawOrder.firstWhere(
        (SceneFace f) => f.sticker != null,
      );
      final Offset center =
          face.corners.reduce((Offset a, Offset b) => a + b) /
          face.corners.length.toDouble();
      final Offset nearEdge = center + (face.corners.first - center) * 0.7;
      expect(big.pick(center), isNotNull);
      expect(big.pick(nearEdge), isNotNull);
      expect(small.pick(nearEdge), isNull);
    });

    test('换视角后同一朝向的面明暗会重新计算（着色缓存含视角）', () async {
      const double size = 200;
      const CubeTheme theme = CubeTheme();
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      for (int i = 0; i < 2; i++) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(i * size, 0, size, size));
        canvas.translate(i * size, 0);
        final CubeScene s = CubeScene(
          state: CubeState(),
          yaw: i == 0 ? -0.62 : 0.3,
          pitch: 0.45,
          viewport: const Size(size, size),
        );
        CubePainter(
          scene: s,
          theme: theme,
        ).paint(canvas, const Size(size, size));
        canvas.restore();
      }
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(
        size.toInt() * 2,
        size.toInt(),
      );
      picture.dispose();
      addTearDown(image.dispose);
      final ByteData? bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(bytes, isNotNull);
      int pixel(int x, int y) {
        final int offset = (y * size.toInt() * 2 + x) * 4;
        return (bytes!.getUint8(offset) << 16) |
            (bytes.getUint8(offset + 1) << 8) |
            bytes.getUint8(offset + 2);
      }

      final int left = pixel(100, 100);
      final int right = pixel(300, 100);
      expect(left, isNot(0), reason: '左侧中心应画有贴纸');
      expect(right, isNot(0), reason: '右侧中心应画有贴纸');
      expect(left, isNot(right), reason: '两个视角下同一世界朝向的面亮度必须不同（旧缓存会冻结颜色）');
    });

    test('shouldRepaint 按内容比较，相同几何不重绘', () {
      final CubeState state = CubeState();
      CubeScene make() => CubeScene(
        state: state,
        yaw: MagicCubeController.defaultYaw,
        pitch: MagicCubeController.defaultPitch,
        viewport: const Size(200, 200),
      );
      final CubePainter a = CubePainter(
        scene: make(),
        theme: const CubeTheme(),
      );
      final CubePainter b = CubePainter(
        scene: make(),
        theme: const CubeTheme(),
      );
      expect(b.shouldRepaint(a), isFalse);
      final CubePainter changed = CubePainter(
        scene: make(),
        theme: const CubeTheme(ambient: 0.2),
      );
      expect(changed.shouldRepaint(a), isTrue);
    });
  });

  group('组件与并发', () {
    Widget cube(
      MagicCubeController controller, {
      bool interactive = true,
      Key? key,
    }) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 240,
            child: MagicCube(
              key: key,
              controller: controller,
              interactive: interactive,
            ),
          ),
        ),
      ),
    );

    Widget plain(MagicCubeController controller, Key key) => SizedBox(
      width: 200,
      height: 200,
      child: MagicCube(key: key, controller: controller),
    );

    testWidgets('orbitBy 打断视角动画时 Future 不再悬挂', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(cube(controller));
      await tester.pump();
      bool done = false;
      final Future<void> animating = controller
          .animateViewToRotation(
            Mat3.fromViewAngles(yaw: 1.2, pitch: 0.8),
            duration: const Duration(seconds: 5),
          )
          .whenComplete(() => done = true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(done, isFalse);
      controller.orbitBy(dx: 0.1);
      await tester.pump();
      expect(done, isTrue, reason: 'gate 必须被这段视角动画的放行逻辑解开');
      await animating;
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });

    testWidgets('手势未结束时编程转动排队，不覆盖手势角度', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController(
        turnDuration: Duration.zero,
      );
      await tester.pumpWidget(cube(controller));
      await tester.pump();
      controller.beginTurn(axis: CubeAxis.y, layer: 2);
      controller.updateTurn(math.pi * 0.6);
      final Future<void> pending = controller.applyMove(CubeMove.parse('R'));
      await tester.pump();
      expect(controller.turnAngle, closeTo(math.pi * 0.6, 1e-9));
      await controller.endTurn();
      await tester.pump();
      await pending;
      expect(controller.moveCount, 2);
      expect(controller.turn, isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });

    testWidgets('两个组件共用控制器，卸载一个不影响另一个的动画', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                plain(controller, const Key('a')),
                plain(controller, const Key('b')),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(children: <Widget>[plain(controller, const Key('b'))]),
          ),
        ),
      );
      await tester.pump();
      unawaited(controller.applyMove(CubeMove.parse('R')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.isAnimating, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isIdle, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });

    testWidgets('拖拽中关闭 interactive 不会落定这一步', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController(
        turnDuration: Duration.zero,
      );
      await tester.pumpWidget(cube(controller));
      await tester.pump();
      controller.beginTurn(axis: CubeAxis.y, layer: 2);
      controller.updateTurn(0.9);
      await tester.pumpWidget(cube(controller, interactive: false));
      await tester.pump();
      expect(controller.turn, isNull);
      expect(controller.moveCount, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  });
}
