import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:magic_cube/magic_cube.dart';
import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'responsive.dart';
import 'session.dart';
import 'widgets/action_bar.dart';
import 'widgets/collapsible_section.dart';
import 'widgets/demo_app_bar.dart';
import 'widgets/move_controls.dart';
import 'widgets/progress_board.dart';
import 'widgets/stats_board.dart';
import 'widgets/timer_header.dart';

void main() => runApp(const MagicCubeExampleApp());

class MagicCubeExampleApp extends StatefulWidget {
  const MagicCubeExampleApp({super.key});

  @override
  State<MagicCubeExampleApp> createState() => _MagicCubeExampleAppState();
}

class _MagicCubeExampleAppState extends State<MagicCubeExampleApp> {
  /// null = follow the device language. Only an explicit choice locks it.
  ui.Locale? _locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: _locale,
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appTitle,
      // Delegates must come from material_ui: flutter_localizations
      // registers flutter/material.dart's MaterialLocalizations, a
      // different type.
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      // Web writes this into <meta name="theme-color">; leaving it unset
      // makes the browser bar use the yellow accent color.
      color: AppPalette.backgroundTop,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppPalette.backgroundTop,
        colorScheme: const ColorScheme.dark(primary: AppPalette.accent),
      ),
      home: CubeDemoPage(
        locale: _locale,
        onLocaleChanged: (ui.Locale? locale) =>
            setState(() => _locale = locale),
      ),
    );
  }
}

class CubeDemoPage extends StatefulWidget {
  const CubeDemoPage({super.key, this.locale, this.onLocaleChanged});

  /// Currently selected language; null means the switcher shows "auto".
  final ui.Locale? locale;
  final ValueChanged<ui.Locale?>? onLocaleChanged;

  @override
  State<CubeDemoPage> createState() => _CubeDemoPageState();
}

class _CubeDemoPageState extends State<CubeDemoPage>
    with SingleTickerProviderStateMixin {
  static final List<CubeTheme> _themes = <CubeTheme>[
    CubeTheme.classic().copyWith(lighting: false),
    CubeTheme.pastel().copyWith(lighting: false),
    CubeTheme.neon().copyWith(lighting: false),
    CubeTheme.flat().copyWith(lighting: false),
  ];

  static List<String> _themeNames(AppLocalizations l10n) => <String>[
    l10n.themeClassic,
    l10n.themePastel,
    l10n.themeNeon,
    l10n.themeFlat,
  ];

  static const double _autoRotateSpeed = 0.25;

  final MagicCubeController _controller = MagicCubeController();
  late final CubeSession _session;

  Ticker? _autoRotateTicker;
  Duration _lastFrameElapsed = Duration.zero;
  bool _autoRotate = false;
  int _themeIndex = 0;

  ui.Image? _logo;
  bool _showLogo = true;

  double _logoScale = 0.75;

  @override
  void initState() {
    super.initState();
    _session = CubeSession(_controller);
    // SingleTickerProviderStateMixin keeps one ticker reference that
    // dispose does not clear; recreating it would hit assert(_ticker == null).
    _autoRotateTicker = createTicker(_onAutoRotateTick);
    unawaited(_loadLogo());
  }

  Future<void> _loadLogo() async {
    final ui.Image image = await renderFlutterLogoToImage(size: 256);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() => _logo = image);
  }

  @override
  void dispose() {
    _autoRotateTicker?.dispose();
    _autoRotateTicker = null;
    // The theme does not dispose images; the caller must.
    _logo?.dispose();
    _logo = null;
    _session.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onAutoRotateTick(Duration elapsed) {
    if (_lastFrameElapsed == Duration.zero) {
      _lastFrameElapsed = elapsed;
      return;
    }
    final double seconds =
        (elapsed - _lastFrameElapsed).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastFrameElapsed = elapsed;
    // orbitBy composes with the current pose; setting yaw directly would
    // discard roll from a flipped view.
    _controller.orbitBy(dx: seconds * _autoRotateSpeed);
  }

  void _toggleAutoRotate(bool value) {
    setState(() => _autoRotate = value);
    if (!value) {
      _autoRotateTicker?.stop();
      return;
    }
    // Ticker aligns with vsync and uses real frame deltas, so dropped
    // frames do not slow rotation.
    _lastFrameElapsed = Duration.zero;
    _autoRotateTicker?.start();
  }

  void _cycleTheme() {
    setState(() => _themeIndex = (_themeIndex + 1) % _themes.length);
  }

  void _handleDoubleTap() {
    switch (_session.phase) {
      case SessionPhase.idle:
      case SessionPhase.finished:
        _session.start();
      case SessionPhase.scrambling:
      case SessionPhase.solving:
        break;
    }
  }

  Widget _actionBar(ActionBarVariant variant) {
    return ActionBar(
      controller: _controller,
      session: _session,
      autoRotate: _autoRotate,
      onAutoRotateChanged: _toggleAutoRotate,
      onCycleTheme: _cycleTheme,
      showLogo: _logo != null && _showLogo,
      onToggleLogo: () => setState(() => _showLogo = !_showLogo),
      variant: variant,
    );
  }

  /// Fixed cube region. It must stay outside every scroll view, or the
  /// scroll recognizer steals layer-turn drags on touch devices.
  Widget _cubeRegion(
    DemoLayout layout,
    AppLocalizations l10n,
    List<String> themeNames, {
    bool showLogoSlider = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TimerHeader(session: _session, fontSize: layout.timerFontSize),
        SizedBox(height: AppPalette.spaceSm),
        Center(
          child: GestureDetector(
            onDoubleTap: _handleDoubleTap,
            child: SizedBox(
              width: layout.cubeSize,
              height: layout.cubeSize,
              child: MagicCube(
                controller: _controller,
                theme: _themes[_themeIndex],
                centerLogo: _showLogo ? _logo : null,
                logoScale: _logoScale,
              ),
            ),
          ),
        ),
        SizedBox(height: AppPalette.spaceXs),
        Text(
          l10n.cubeInfo(themeNames[_themeIndex]),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppPalette.statLabel,
        ),
        if (showLogoSlider && _logo != null) _logoSlider(l10n, layout),
      ],
    );
  }

  Widget _logoSlider(AppLocalizations l10n, DemoLayout layout) {
    final String percent = '${(_logoScale * 100).round()}%';
    final Widget value = Text(
      percent,
      textAlign: TextAlign.right,
      style: AppPalette.statValue,
    );
    final Widget slider = Slider(
      value: _logoScale,
      min: 0.1,
      max: 1,
      divisions: 18,
      label: percent,
      onChanged: (double value) => setState(() => _logoScale = value),
    );
    // On phones the label / value / slider stack instead of squeezing into
    // one row that would truncate the label.
    if (layout.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.logoSizeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppPalette.statLabel,
                ),
              ),
              SizedBox(width: 44, child: value),
            ],
          ),
          slider,
        ],
      );
    }
    return Row(
      children: <Widget>[
        Text(l10n.logoSizeLabel, style: AppPalette.statLabel),
        Expanded(child: slider),
        SizedBox(width: 44, child: value),
      ],
    );
  }

  Widget _dataPanels(DemoLayout layout) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppMetrics.panelSpacing,
      runSpacing: AppMetrics.panelSpacing,
      children: <Widget>[
        StatsBoard(session: _session, width: layout.panelWidth),
        ProgressBoard(controller: _controller, width: layout.panelWidth),
      ],
    );
  }

  /// All secondary information, fully expanded on tablet / desktop.
  Widget _infoColumn(DemoLayout layout, {required bool includePrimary}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (includePrimary) ...<Widget>[
          _actionBar(ActionBarVariant.primary),
          SizedBox(height: layout.sectionGap),
        ],
        _dataPanels(layout),
        SizedBox(height: layout.sectionGap),
        _actionBar(ActionBarVariant.secondary),
        SizedBox(height: layout.sectionGap),
        MoveControls(controller: _controller),
      ],
    );
  }

  /// Phone: core actions first, secondary content collapsed by default.
  Widget _compactContent(DemoLayout layout, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _actionBar(ActionBarVariant.primary),
        SizedBox(height: layout.sectionGap),
        CollapsibleSection(
          title: l10n.sectionData,
          icon: Icons.history,
          initiallyExpanded: !layout.collapseSecondary,
          child: _dataPanels(layout),
        ),
        SizedBox(height: layout.sectionGap),
        CollapsibleSection(
          title: l10n.sectionMoves,
          icon: Icons.shuffle,
          initiallyExpanded: !layout.collapseSecondary,
          child: MoveControls(controller: _controller),
        ),
        if (_logo != null) ...<Widget>[
          SizedBox(height: layout.sectionGap),
          CollapsibleSection(
            title: l10n.sectionAppearance,
            icon: Icons.palette,
            initiallyExpanded: !layout.collapseSecondary,
            child: _logoSlider(l10n, layout),
          ),
        ],
      ],
    );
  }

  Widget _expandedBody(
    DemoLayout layout,
    AppLocalizations l10n,
    List<String> themeNames,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: layout.leftColumnWidth,
          child: Padding(
            padding: EdgeInsets.all(layout.gutter),
            child: _cubeRegion(layout, l10n, themeNames),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.only(
              top: layout.sectionGap,
              right: layout.gutter,
              bottom: AppPalette.spaceLg,
            ),
            child: _infoColumn(layout, includePrimary: false),
          ),
        ),
      ],
    );
  }

  Widget _stackedBody(
    DemoLayout layout,
    AppLocalizations l10n,
    List<String> themeNames,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            layout.gutter,
            layout.sectionGap,
            layout.gutter,
            0,
          ),
          child: _cubeRegion(
            layout,
            l10n,
            themeNames,
            showLogoSlider: !layout.isCompact,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.only(
              top: layout.sectionGap,
              left: layout.gutter,
              right: layout.gutter,
              bottom: AppPalette.spaceLg,
            ),
            child: layout.isCompact
                ? _compactContent(layout, l10n)
                : _infoColumn(layout, includePrimary: true),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<String> themeNames = _themeNames(l10n);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppPalette.background),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // One layout decision for the whole subtree; children only
              // consume the resulting metrics instead of re-reading MediaQuery.
              final DemoLayout layout = DemoLayout.from(
                constraints,
                MediaQuery.sizeOf(context),
              );
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: layout.contentWidth),
                  child: DemoAppBar(
                    layout: layout,
                    quickActions: _actionBar(ActionBarVariant.primary),
                    menu: _actionBar(ActionBarVariant.menu),
                    locale: widget.locale,
                    onLocaleChanged: widget.onLocaleChanged,
                    body: layout.isExpanded
                        ? _expandedBody(layout, l10n, themeNames)
                        : _stackedBody(layout, l10n, themeNames),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
