import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:magic_cube_example/app_theme.dart';
import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:magic_cube_example/session.dart';
import 'package:magic_cube_example/widgets/action_bar.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n_test_utils.dart';

void main() {
  testWidgets('点「打乱」之后撤销与逐步还原会变为可用', (WidgetTester tester) async {
    const Locale locale = Locale('zh');
    final AppLocalizations l10n = l10nFor(locale);
    final MagicCubeController controller = MagicCubeController();
    final CubeSession session = CubeSession(controller);
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      localizedTestApp(
        ActionBar(
          controller: controller,
          session: session,
          autoRotate: false,
          onAutoRotateChanged: (bool _) {},
          onCycleTheme: () {},
          showLogo: false,
          onToggleLogo: () {},
        ),
        locale: locale,
      ),
    );
    await tester.pump();

    // 默认变体必须保持原来的 8 个动作，向后兼容单独使用本组件的调用方。
    expect(find.byType(AppButton), findsNWidgets(8));

    VoidCallback? onTapOf(String label) => tester
        .widget<InkWell>(
          find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
        )
        .onTap;

    expect(onTapOf(l10n.actionUndo), isNull, reason: '还没有任何转动时应当不可点');
    expect(onTapOf(l10n.actionUndoAll), isNull);

    // Direct scramble() goes through the controller, not
    // CubeSession.start, so the session emits no notification.
    await tester.tap(find.text(l10n.actionScramble));
    for (int i = 0; i < 60 && controller.moveCount < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.moveCount, 20);

    expect(
      onTapOf(l10n.actionUndo),
      isNotNull,
      reason: '打乱之后必须能撤销；页面没有重建的话这个按钮会一直是灰的',
    );
    expect(onTapOf(l10n.actionUndoAll), isNotNull);

    await tester.tap(find.text(l10n.actionUndo));
    for (int i = 0; i < 20 && controller.moveCount > 19; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.moveCount, 19);
  });
}
