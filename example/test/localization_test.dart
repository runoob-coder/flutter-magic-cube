import 'package:flutter_test/flutter_test.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:magic_cube_example/main.dart';
import 'package:magic_cube_example/session.dart';
import 'package:magic_cube_example/widgets/action_bar.dart';
import 'package:magic_cube_example/widgets/move_controls.dart';
import 'package:magic_cube_example/widgets/progress_board.dart';
import 'package:magic_cube_example/widgets/stats_board.dart';
import 'package:magic_cube_example/widgets/timer_header.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n_test_utils.dart';

void main() {
  const Locale en = Locale('en');
  const Locale zh = Locale('zh');

  test('响应式新增文案在中英文下都有译文', () {
    final AppLocalizations enL10n = l10nFor(en);
    final AppLocalizations zhL10n = l10nFor(zh);
    final List<String> english = <String>[
      enL10n.navTitle,
      enL10n.navMenuLabel,
      enL10n.navMenuOpenHint,
      enL10n.navMenuCloseHint,
      enL10n.sectionData,
      enL10n.sectionMoves,
      enL10n.sectionAppearance,
      enL10n.expandHint,
      enL10n.collapseHint,
      enL10n.languageLabel,
      enL10n.languageSystem,
      enL10n.languageEnglish,
      enL10n.languageChinese,
      enL10n.languageMenuOpenHint,
      enL10n.languageMenuCloseHint,
    ];
    final List<String> chinese = <String>[
      zhL10n.navTitle,
      zhL10n.navMenuLabel,
      zhL10n.navMenuOpenHint,
      zhL10n.navMenuCloseHint,
      zhL10n.sectionData,
      zhL10n.sectionMoves,
      zhL10n.sectionAppearance,
      zhL10n.expandHint,
      zhL10n.collapseHint,
      zhL10n.languageLabel,
      zhL10n.languageSystem,
      zhL10n.languageEnglish,
      zhL10n.languageChinese,
      zhL10n.languageMenuOpenHint,
      zhL10n.languageMenuCloseHint,
    ];
    expect(english, hasLength(chinese.length));
    for (int i = 0; i < english.length; i++) {
      expect(english[i], isNot(chinese[i]), reason: '第 $i 条文案应完成互译');
    }
  });

  testWidgets('英文与中文各自显示对应文案', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    final CubeSession session = CubeSession(controller);
    addTearDown(session.dispose);
    addTearDown(controller.dispose);

    Widget sample() => SingleChildScrollView(
      child: Column(
        children: <Widget>[
          TimerHeader(session: session),
          StatsBoard(session: session),
          ProgressBoard(controller: controller),
          MoveControls(controller: controller),
          ActionBar(
            controller: controller,
            session: session,
            autoRotate: false,
            onAutoRotateChanged: (bool _) {},
            onCycleTheme: () {},
            showLogo: false,
            onToggleLogo: () {},
          ),
        ],
      ),
    );

    for (final Locale locale in <Locale>[en, zh]) {
      final AppLocalizations l10n = l10nFor(locale);
      final AppLocalizations other = l10nFor(locale == en ? zh : en);
      await tester.pumpWidget(localizedTestApp(sample(), locale: locale));
      await tester.pump();

      expect(find.text(l10n.statusIdle), findsOneWidget);
      expect(find.text(l10n.statsPanelTitle), findsOneWidget);
      expect(find.text(l10n.statsTotalSolves), findsOneWidget);
      expect(find.text(l10n.statsAverageOf12), findsOneWidget);
      expect(find.text(l10n.progressPanelTitle), findsOneWidget);
      expect(find.text(l10n.progressHint), findsOneWidget);
      expect(find.text(l10n.movesPanelTitle), findsOneWidget);
      expect(find.text(l10n.actionScramble), findsOneWidget);
      expect(find.text(l10n.actionUndo), findsOneWidget);

      expect(find.text(other.statusIdle), findsNothing);
      expect(find.text(other.progressHint), findsNothing);
      expect(find.text(other.actionScramble), findsNothing);
    }
  });

  testWidgets('跟随系统语言切换；缓存面板与错误提示不残留旧语言', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    final CubeSession session = CubeSession(controller);
    addTearDown(session.dispose);
    addTearDown(controller.dispose);
    final AppLocalizations enL10n = l10nFor(en);
    final AppLocalizations zhL10n = l10nFor(zh);

    // Drive the switch via system locales (production sets no locale)
    // after pumping, so Localizations observers are registered first.
    addTearDown(() => tester.binding.setLocales(<Locale>[en]));

    await tester.pumpWidget(
      localizedTestApp(
        SingleChildScrollView(
          child: Column(
            children: <Widget>[
              TimerHeader(session: session),
              ProgressBoard(controller: controller),
              MoveControls(controller: controller),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.binding.setLocales(<Locale>[zh]);
    await tester.pump();
    await tester.pump();

    expect(find.text(zhL10n.statusIdle), findsOneWidget);
    expect(find.text(zhL10n.progressHint), findsOneWidget);
    expect(find.text(zhL10n.movesPanelTitle), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ZZ');
    await tester.ensureVisible(find.text(zhL10n.movesRun));
    await tester.tap(find.text(zhL10n.movesRun));
    await tester.pump();
    expect(find.text(zhL10n.movesError), findsOneWidget);

    await tester.binding.setLocales(<Locale>[en]);
    await tester.pump();
    await tester.pump();

    expect(find.text(enL10n.statusIdle), findsOneWidget);
    expect(find.text(enL10n.progressPanelTitle), findsOneWidget);
    expect(find.text(enL10n.progressHint), findsOneWidget);
    expect(find.text(enL10n.movesError), findsOneWidget);
    expect(find.text(zhL10n.statusIdle), findsNothing);
    expect(find.text(zhL10n.progressHint), findsNothing);
    expect(find.text(zhL10n.movesError), findsNothing);
  });

  testWidgets('中文变体回落到中文，未支持语言回落到英文', (WidgetTester tester) async {
    final MagicCubeController controller = MagicCubeController();
    final CubeSession session = CubeSession(controller);
    addTearDown(session.dispose);
    addTearDown(controller.dispose);
    final AppLocalizations enL10n = l10nFor(en);
    final AppLocalizations zhL10n = l10nFor(zh);

    for (final Locale locale in <Locale>[
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
        countryCode: 'CN',
      ),
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
      const Locale('zh', 'HK'),
    ]) {
      await tester.pumpWidget(
        localizedTestApp(TimerHeader(session: session), locale: locale),
      );
      await tester.pump();
      expect(
        find.text(zhL10n.statusIdle),
        findsOneWidget,
        reason: '$locale 应当回落到中文',
      );
      expect(find.text(enL10n.statusIdle), findsNothing);
    }

    for (final Locale locale in <Locale>[
      const Locale('fr'),
      const Locale('ja'),
    ]) {
      await tester.pumpWidget(
        localizedTestApp(TimerHeader(session: session), locale: locale),
      );
      await tester.pump();
      expect(
        find.text(enL10n.statusIdle),
        findsOneWidget,
        reason: '$locale 应当回落到英文',
      );
      expect(find.text(zhL10n.statusIdle), findsNothing);
    }
  });

  testWidgets('生产入口默认跟随系统，并装配中英委托与本地化标题', (WidgetTester tester) async {
    // MagicCubeExampleApp now owns the language choice, so inspect the
    // mounted MaterialApp instead of calling build() on it directly.
    await tester.pumpWidget(const MagicCubeExampleApp());
    await tester.pump();
    final MaterialApp app = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );

    expect(app.locale, isNull, reason: '不设置 locale 才会跟随系统语言');
    expect(app.supportedLocales, AppLocalizations.supportedLocales);
    expect(app.onGenerateTitle, isNotNull);
    expect(
      app.localizationsDelegates,
      hasLength(4),
      reason: 'AppLocalizations + material_ui 的 3 个 Global delegate',
    );

    for (final Locale locale in <Locale>[en, zh]) {
      await tester.pumpWidget(
        localizedTestApp(const SizedBox.shrink(), locale: locale),
      );
      await tester.pump();
      final BuildContext localizedContext = tester.element(
        find.byType(Scaffold),
      );
      expect(app.onGenerateTitle!(localizedContext), l10nFor(locale).appTitle);
    }
    expect(l10nFor(en).appTitle, isNot(l10nFor(zh).appTitle));
  });

  testWidgets('右上角可切换语言：默认跟随系统、选择后覆盖、可恢复跟随', (WidgetTester tester) async {
    final AppLocalizations enL10n = l10nFor(en);
    final AppLocalizations zhL10n = l10nFor(zh);
    addTearDown(() => tester.binding.setLocales(<Locale>[en]));

    // 先挂载页面（Localizations 注册 observer 之后）再派发系统语言变化，
    // 否则 setLocales 没有监听者，首次解析仍使用默认语言。
    await tester.pumpWidget(const MagicCubeExampleApp());
    await tester.pump();
    expect(find.text(enL10n.statusIdle), findsOneWidget);
    await tester.binding.setLocales(<Locale>[zh]);
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      isNull,
      reason: '未手动选择时不应锁定 locale',
    );
    expect(find.text(zhL10n.statusIdle), findsOneWidget, reason: '应跟随系统中文');
    expect(find.text('AUTO'), findsOneWidget, reason: '未手动选择时显示 AUTO');

    // 手动选英语：覆盖系统中文。
    await tester.tap(find.text('AUTO'));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('language-menu'))).width,
      lessThanOrEqualTo(240),
      reason: '语言菜单应是紧凑下拉，不能占满屏宽',
    );
    expect(find.byIcon(Icons.brightness_auto), findsOneWidget);
    expect(find.byIcon(Icons.abc), findsOneWidget);
    expect(find.byIcon(Icons.translate), findsOneWidget);
    expect(find.text(zhL10n.languageSystem), findsOneWidget);
    expect(find.text(zhL10n.languageEnglish), findsOneWidget);
    await tester.tap(find.text(zhL10n.languageEnglish));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).locale, en);
    expect(find.text(enL10n.statusIdle), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);

    // 系统语言来回变化不应改变已选择的语言。
    await tester.binding.setLocales(<Locale>[en]);
    await tester.pump();
    await tester.binding.setLocales(<Locale>[zh]);
    await tester.pump();
    await tester.pump();
    expect(find.text(enL10n.statusIdle), findsOneWidget);
    expect(find.text(zhL10n.statusIdle), findsNothing);

    // 选择「跟随系统」：重新跟随中文系统语言。
    await tester.tap(find.text('EN'));
    await tester.pump();
    await tester.tap(find.text(enL10n.languageSystem));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).locale, isNull);
    expect(find.text(zhL10n.statusIdle), findsOneWidget);
    expect(find.text('AUTO'), findsOneWidget);
  });
}
