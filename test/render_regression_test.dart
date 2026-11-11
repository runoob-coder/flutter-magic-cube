import 'dart:async';
import 'dart:ui' show Canvas, Picture, PictureRecorder, Size;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:material_ui/material_ui.dart';

const Size kVp = Size(320, 320);

Widget _app(MagicCubeController controller) => MaterialApp(
  home: Scaffold(
    body: Center(child: MagicCube(controller: controller)),
  ),
);

CubeScene _turningScene(CubeState state, double angle) => CubeScene(
  state: state,
  turn: CubeTurn(axis: CubeAxis.y, layer: 2, angle: angle),
  yaw: MagicCubeController.defaultYaw,
  pitch: MagicCubeController.defaultPitch,
  viewport: kVp,
);

int _paintBytes(CubePainter painter) {
  final PictureRecorder recorder = PictureRecorder();
  painter.paint(Canvas(recorder), kVp);
  final Picture picture = recorder.endRecording();
  final int bytes = picture.approximateBytesUsed;
  picture.dispose();
  return bytes;
}

void main() {
  group('静止层缓存', () {
    setUp(CubeScene.disposeSceneCache);

    test('同一个魔方连续两帧复用同一批静止面', () {
      final CubeState state = CubeState();
      final CubeScene first = _turningScene(state, 0.01);
      final CubeScene second = _turningScene(state, 0.02);
      expect(first.hasLayerSegments, isTrue);
      expect(
        identical(second.facesBeforeTurning, first.facesBeforeTurning),
        isTrue,
      );
    });

    test('两个魔方交替渲染时缓存不再互相踢掉', () {
      // A single global cache used to be evicted by a second cube on
      // screen.
      final CubeState a = CubeState();
      final CubeState b = CubeState()..applyMove(CubeMove.parse('R'));

      final CubeScene first = _turningScene(a, 0.01);
      _turningScene(b, 0.01);
      final CubeScene again = _turningScene(a, 0.02);

      expect(
        identical(again.facesBeforeTurning, first.facesBeforeTurning),
        isTrue,
      );
      expect(
        identical(again.facesAfterTurning, first.facesAfterTurning),
        isTrue,
      );
    });

    test('超过容量后按最近最少使用淘汰', () {
      const int capacity = 4;
      final List<CubeState> states = <CubeState>[
        for (int i = 0; i < capacity + 2; i++)
          CubeState()..applyMove(CubeMove.parse('U')),
      ];
      final List<CubeScene> scenes = <CubeScene>[
        for (final CubeState s in states) _turningScene(s, 0.01),
      ];
      expect(CubeScene.disposeSceneCache(), lessThanOrEqualTo(capacity));
      final CubeScene rebuilt = _turningScene(states.last, 0.05);
      expect(
        rebuilt.facesBeforeTurning.length,
        scenes.last.facesBeforeTurning.length,
      );
    });
  });

  group('渲染缓存释放', () {
    test('disposeCaches 之后还能正常重录', () {
      final CubePainter painter = CubePainter(
        scene: _turningScene(CubeState(), 0.01),
        theme: const CubeTheme(),
      );
      expect(_paintBytes(painter), greaterThan(0));
      CubePainter.disposeCaches();
      expect(_paintBytes(painter), greaterThan(0));
    });

    testWidgets('最后一个魔方卸载后不残留场景缓存', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      await tester.pump();

      unawaited(controller.applyMove(CubeMove.parse('R')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        CubeScene.disposeSceneCache(),
        isPositive,
        reason: '转动进行中应当已经写出静止层缓存',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      controller.dispose();
      expect(CubeScene.disposeSceneCache(), 0, reason: '组件卸载时应当已经清空');
    });
  });

  group('渲染隔离', () {
    testWidgets('魔方画布被隔离在自己的合成层里', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      await tester.pump();

      int count = 0;
      void walk(RenderObject object) {
        if (object is RenderRepaintBoundary) count++;
        object.visitChildren(walk);
      }

      walk(tester.renderObject(find.byType(MagicCube)));
      // isComplex/willChange do not create a compositing layer; without
      // a RepaintBoundary siblings are repainted too.
      expect(count, greaterThanOrEqualTo(1));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  });

  group('动画生命周期', () {
    testWidgets('stopAnimation 之后立刻回到空闲', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      await tester.pump();

      unawaited(controller.applyNotation("R U R' U'"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.isIdle, isFalse);

      controller.stopAnimation();
      await tester.pump();
      expect(controller.turn, isNull);
      expect(controller.isIdle, isTrue, reason: '停止后必须立刻可用');

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });

    testWidgets('stopAnimation 之后的 Future 立刻返回', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      await tester.pump();

      final Future<void> scrambling = controller.scramble(length: 12);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.isIdle, isFalse);

      controller.stopAnimation();
      await tester.pump();
      // No Timer-based timeout: fake async never advances timers by
      // itself.
      await scrambling;
      expect(controller.isIdle, isTrue);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });

    testWidgets('dispose 时等待中的转动会放行', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      await tester.pump();

      final Future<void> moving = controller.applyMove(CubeMove.parse('R'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      controller.dispose();
      // AnimationController.dispose also leaves forward()'s future
      // pending.
      await moving;
      expect(controller.isDisposed, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reset 会停掉进行中的视角动画', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      await tester.pump();

      final Future<void> animating = controller.animateViewToRotation(
        Mat3.fromViewAngles(yaw: 1.2, pitch: 0.8),
        duration: const Duration(seconds: 5),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      controller.reset();
      await animating;

      await tester.pump(const Duration(seconds: 5));
      expect(controller.yaw, isNot(closeTo(1.2, 1e-3)));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });

    testWidgets('手势拖拽可以打断正在播放的视角动画', (WidgetTester tester) async {
      final MagicCubeController controller = MagicCubeController();
      await tester.pumpWidget(_app(controller));
      await tester.pump();

      unawaited(
        controller.animateViewToRotation(
          Mat3.fromViewAngles(yaw: 1.2, pitch: 0.8),
          duration: const Duration(seconds: 5),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final Mat3 grabbed = controller.viewRotation;
      controller.orbitBy(dx: 0.1);
      await tester.pump(const Duration(seconds: 5));
      expect(controller.isAnimating, isFalse);
      expect(controller.yaw, isNot(closeTo(1.2, 1e-3)));
      expect(controller.viewRotation, isNot(grabbed));

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  });
}
