import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:material_ui/material_ui.dart';

Future<({CubeMove? move, Vec3 before})> _turnOnce(
  WidgetTester tester, {
  required Vec3 corner,
  required Offset sweep,
  int which = 0,
}) async {
  final MagicCubeController controller = MagicCubeController();
  CubeMove? recorded;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: MagicCube(
            controller: controller,
            onMove: (CubeMove move) => recorded = move,
          ),
        ),
      ),
    ),
  );
  await tester.pump();

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
    (Cubie c) => c.position == corner,
  );
  expect(index, isNot(-1), reason: '找不到位于 $corner 的小方块');

  final List<SceneFace> faces = scene.drawOrder
      .where((SceneFace f) => f.cubieIndex == index && f.sticker != null)
      .toList();
  expect(faces.length, greaterThan(which));
  final SceneFace face = faces[which];
  double x = 0;
  double y = 0;
  for (final Offset p in face.corners) {
    x += p.dx;
    y += p.dy;
  }
  final Offset local = Offset(x / face.corners.length, y / face.corners.length);
  final Vec3 before = controller.state.cubies[index].position;

  final Offset target = tester.getTopLeft(find.byType(MagicCube)) + local;
  await tester.dragFrom(target, sweep);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  await tester.pumpWidget(const SizedBox());
  controller.dispose();
  return (move: recorded, before: before);
}

void main() {
  group('拧层落点', () {
    // This corner is visible in the default view and lies on all three
    // outer layers.
    const Vec3 corner = Vec3(1, 1, 1);

    final Map<String, Offset> sweeps = <String, Offset>{
      '向右拖': const Offset(320, 0),
      '向左拖': const Offset(-320, 0),
      '向下拖': const Offset(0, 320),
      '向上拖': const Offset(0, -320),
      '右下拖': const Offset(230, 230),
      '左上拖': const Offset(-230, -230),
      '右上拖': const Offset(230, -230),
      '左下拖': const Offset(-230, 230),
    };

    testWidgets('无论往哪个方向拖，转动的都是被触摸的那一层', (WidgetTester tester) async {
      final List<String> skipped = <String>[];
      int checked = 0;
      for (final MapEntry<String, Offset> entry in sweeps.entries) {
        final ({CubeMove? move, Vec3 before}) result = await _turnOnce(
          tester,
          corner: corner,
          sweep: entry.value,
        );

        // Drags under 90 degrees snap back without committing a move.
        if (result.move == null) {
          skipped.add(entry.key);
          continue;
        }
        checked++;
        final CubeMove move = result.move!;
        // Layer indices are measured along the positive axis: layer 0 is
        // -halfExtent.
        final double expected = move.layer - 1;
        expect(
          result.before[move.axis],
          closeTo(expected, 1e-9),
          reason:
              '${entry.key}：碰的是 ${result.before}，'
              '却转到了 ${move.axis} 轴的第 ${move.layer} 层',
        );
      }
      expect(
        checked,
        sweeps.length,
        reason: '只有 $checked 个方向产生了转动，跳过了 $skipped',
      );
    });

    testWidgets('角块的三个可见面都能落在正确的层上', (WidgetTester tester) async {
      final Set<CubeAxis> seen = <CubeAxis>{};
      int checked = 0;
      for (int which = 0; which < 3; which++) {
        final ({CubeMove? move, Vec3 before}) result = await _turnOnce(
          tester,
          corner: corner,
          sweep: const Offset(320, 0),
          which: which,
        );
        if (result.move == null) continue;
        checked++;
        final CubeMove move = result.move!;
        seen.add(move.axis);
        expect(
          result.before[move.axis],
          closeTo(move.layer - 1, 1e-9),
          reason:
              '第 $which 个面：碰的是 ${result.before}，'
              '却转到了 ${move.axis} 轴的第 ${move.layer} 层',
        );
      }
      expect(
        checked,
        greaterThanOrEqualTo(2),
        reason: '至少要有 2 个面的拖拽产生转动，实际 $checked',
      );
      expect(seen.length, greaterThanOrEqualTo(2), reason: '转轴集合为 $seen');
    });

    testWidgets('滑块的内部层同样不会被镜像', (WidgetTester tester) async {
      final ({CubeMove? move, Vec3 before}) result = await _turnOnce(
        tester,
        corner: const Vec3(1, 1, 0),
        sweep: const Offset(320, 0),
      );
      expect(result.move, isNotNull);
      final CubeMove move = result.move!;
      expect(result.before[move.axis], closeTo(move.layer - 1, 1e-9));
      expect(move.layer, 1, reason: 'z 坐标为 0 的块应当落在中间那一层');
    });
  });
}
