import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:magic_cube_example/app_theme.dart';
import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:magic_cube_example/main.dart';
import 'package:magic_cube_example/responsive.dart';
import 'package:magic_cube_example/widgets/collapsible_section.dart';
import 'package:magic_cube_example/widgets/demo_app_bar.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n_test_utils.dart';

const Locale _zh = Locale('zh');

Future<void> _pumpPage(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(localizedTestApp(const CubeDemoPage(), locale: _zh));
  // _loadLogo() is unawaited; give it a frame so the appearance section
  // (which only exists once the logo is ready) can settle either way.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _panelOf(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Panel));

void main() {
  testWidgets('手机：核心操作常驻，次要内容默认折叠，菜单可展开', (WidgetTester tester) async {
    final AppLocalizations l10n = l10nFor(_zh);
    await _pumpPage(tester, const Size(390, 844));

    expect(find.byType(DemoAppBar), findsOneWidget);
    expect(find.text(l10n.navMenuLabel), findsOneWidget);
    expect(find.text(l10n.actionScramble), findsOneWidget);
    expect(find.text(l10n.sectionData), findsOneWidget);
    expect(find.text(l10n.sectionMoves), findsOneWidget);
    // Collapsed sections do not build their children at all.
    expect(find.text(l10n.statsPanelTitle), findsNothing);
    expect(find.text(l10n.progressPanelTitle), findsNothing);
    expect(find.text(l10n.movesPanelTitle), findsNothing);
    expect(find.byType(CollapsibleSection), findsWidgets);

    // Every visible pill button has a touch-friendly target.
    final int buttonCount = find.byType(AppButton).evaluate().length;
    expect(buttonCount, greaterThan(0));
    for (int i = 0; i < buttonCount; i++) {
      expect(
        tester.getRect(find.byType(AppButton).at(i)).height,
        greaterThanOrEqualTo(AppMetrics.minTouchTarget - 0.01),
        reason: '按钮 $i 的点击区应不小于 ${AppMetrics.minTouchTarget}',
      );
      expect(
        tester.getRect(find.byType(AppButton).at(i)).width,
        lessThan(300),
        reason: '按钮 $i 不应被拉伸成整行宽',
      );
    }

    // The compact top bar opens a full action list.
    await tester.tap(find.text(l10n.navMenuLabel));
    await tester.pump();
    expect(find.text(l10n.actionTheme), findsOneWidget);
    expect(find.text(l10n.actionResetView), findsOneWidget);
    await tester.tap(find.text(l10n.navMenuLabel));
    await tester.pump();

    // Expanding a section reveals its content.
    await tester.tap(find.text(l10n.sectionData));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text(l10n.statsPanelTitle), findsOneWidget);
    expect(find.text(l10n.progressPanelTitle), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '窄屏不应出现布局溢出');
  });

  testWidgets('平板：内容全部展开，两个数据面板并排', (WidgetTester tester) async {
    final AppLocalizations l10n = l10nFor(_zh);
    await _pumpPage(tester, const Size(768, 1024));

    expect(find.byType(CollapsibleSection), findsNothing);
    expect(find.text(l10n.statsPanelTitle), findsOneWidget);
    expect(find.text(l10n.progressPanelTitle), findsOneWidget);
    expect(find.text(l10n.movesPanelTitle), findsOneWidget);
    expect(find.text(l10n.navMenuLabel), findsOneWidget);

    final stats = tester.getRect(_panelOf(l10n.statsPanelTitle));
    final progress = tester.getRect(_panelOf(l10n.progressPanelTitle));
    expect(stats.top, closeTo(progress.top, 1), reason: '两块面板应并排');
    expect(stats.right, lessThan(progress.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面：左魔方右信息的双栏，顶部栏显示快捷操作', (WidgetTester tester) async {
    final AppLocalizations l10n = l10nFor(_zh);
    await _pumpPage(tester, const Size(1440, 900));

    expect(find.byType(CollapsibleSection), findsNothing);
    expect(find.text(l10n.navMenuLabel), findsNothing);
    expect(find.text(l10n.actionTheme), findsOneWidget);
    expect(find.text(l10n.statsPanelTitle), findsOneWidget);

    final cube = tester.getRect(find.byType(MagicCube));
    final stats = tester.getRect(_panelOf(l10n.statsPanelTitle));
    expect(cube.right, lessThan(stats.left), reason: '魔方应在左栏');
    expect(stats.right, lessThan(1440));
    // 桌面顶部栏直接显示核心快捷操作（拧乱 / 撤销 / 复原），长英文文案也不能换行溢出。
    expect(find.text(l10n.actionScramble), findsOneWidget);
    expect(find.text(l10n.actionUndo), findsOneWidget);
    expect(find.text(l10n.actionResetCube), findsOneWidget);
    final Rect scrambleBtn = tester.getRect(
      find.ancestor(
        of: find.text(l10n.actionScramble),
        matching: find.byType(AppButton),
      ),
    );
    final Rect resetCubeBtn = tester.getRect(
      find.ancestor(
        of: find.text(l10n.actionResetCube),
        matching: find.byType(AppButton),
      ),
    );
    expect(
      scrambleBtn.top,
      closeTo(resetCubeBtn.top, 1),
      reason: '三个核心操作应在同一行，不能换行',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('横屏矮屏：魔方按可用高度收缩且无溢出', (WidgetTester tester) async {
    await _pumpPage(tester, const Size(844, 390));
    final cube = tester.getRect(find.byType(MagicCube));
    expect(cube.height, lessThan(390));
    expect(tester.takeException(), isNull);
  });
}
