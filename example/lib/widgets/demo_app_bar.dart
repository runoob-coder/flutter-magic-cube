import 'dart:async';
import 'dart:math' as math;

import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../responsive.dart';

/// Source repository on GitHub, opened by the header link button.
const String _githubUrl = 'https://github.com/runoob-coder/flutter-magic-cube';

/// Which overlay is currently open. Only one can be open at a time.
enum _OpenMenu { none, actions, language }

/// Responsive top bar plus the page body it sits above.
///
/// On wide screens the frequent actions are shown inline. On phones and
/// tablets the bar shrinks to a title plus two buttons: one for the action
/// list and one for the language switcher. Menus are drawn as overlays so
/// they never squeeze the (fixed, non-scrolling) cube region.
class DemoAppBar extends StatefulWidget {
  const DemoAppBar({
    super.key,
    required this.layout,
    required this.quickActions,
    required this.menu,
    required this.body,
    this.locale,
    this.onLocaleChanged,
  });

  final DemoLayout layout;

  /// Shown inline on wide screens.
  final Widget quickActions;

  /// Full action list shown inside the compact-screen menu.
  final Widget menu;

  /// Everything below the top bar.
  final Widget body;

  /// Currently selected language, or null to follow the device language.
  final Locale? locale;

  /// Null disables the language switcher (e.g. when the bar is used alone).
  final ValueChanged<Locale?>? onLocaleChanged;

  @override
  State<DemoAppBar> createState() => _DemoAppBarState();
}

class _DemoAppBarState extends State<DemoAppBar> {
  /// The language menu is a compact drop-down, not a full-width panel.
  static const double _languageMenuWidth = 240;

  _OpenMenu _open = _OpenMenu.none;

  bool get _languageEnabled => widget.onLocaleChanged != null;

  @override
  void didUpdateWidget(covariant DemoAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resizing to a wide screen shows all actions inline again.
    if (widget.layout.inlineHeaderActions && _open == _OpenMenu.actions) {
      _open = _OpenMenu.none;
    }
  }

  void _chooseLanguage(Locale? locale) {
    setState(() => _open = _OpenMenu.none);
    widget.onLocaleChanged?.call(locale);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool showMenuButton = !widget.layout.inlineHeaderActions;
    final bool menuOpen = _open != _OpenMenu.none;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double menuMaxHeight = math.max(
          120,
          constraints.maxHeight -
              AppMetrics.headerHeight -
              widget.layout.gutter * 2,
        );
        final double languageMenuWidth = math.min(
          _languageMenuWidth,
          math.max(160, constraints.maxWidth - widget.layout.gutter * 2),
        );
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _header(l10n, showMenuButton),
                Expanded(child: widget.body),
              ],
            ),
            if (menuOpen) ...<Widget>[
              // Tap anywhere outside a menu (but below the bar) to close it.
              Positioned(
                top: AppMetrics.headerHeight,
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _open = _OpenMenu.none),
                ),
              ),
              if (_open == _OpenMenu.language)
                // Right-aligned drop-down: keep it narrow on both desktop
                // and phones instead of stretching across the whole screen.
                Positioned(
                  top: AppMetrics.headerHeight + AppPalette.spaceXs,
                  right: widget.layout.gutter,
                  child: SizedBox(
                    key: const Key('language-menu'),
                    width: languageMenuWidth,
                    child: _menuPanel(
                      _languageOptions(l10n),
                      padding: AppPalette.spaceXs,
                    ),
                  ),
                )
              else
                Positioned(
                  top: AppMetrics.headerHeight + AppPalette.spaceXs,
                  left: widget.layout.gutter,
                  right: widget.layout.gutter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: menuMaxHeight),
                    child: _menuPanel(widget.menu),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _header(AppLocalizations l10n, bool showMenuButton) {
    final Widget leading = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.threed_rotation, color: AppPalette.accent, size: 22),
        const SizedBox(width: AppPalette.spaceSm),
        Text(
          l10n.navTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppPalette.statValue.copyWith(fontSize: 16),
        ),
      ],
    );
    final List<Widget> trailing = <Widget>[
      if (showMenuButton) _menuButton(l10n) else widget.quickActions,
      if (_languageEnabled) ...<Widget>[
        const SizedBox(width: AppPalette.spaceXs),
        _languageButton(l10n),
      ],
      const SizedBox(width: AppPalette.spaceXs),
      _githubButton(l10n),
    ];

    return Container(
      height: AppMetrics.headerHeight,
      padding: EdgeInsets.symmetric(horizontal: widget.layout.gutter),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppPalette.border)),
      ),
      child: Row(
        // The title stays on the left; the expanding spacer pushes the
        // actions (quick actions on desktop, the menu button on smaller
        // screens) plus the language and GitHub buttons to the right.
        children: <Widget>[
          Expanded(child: leading),
          ...trailing,
        ],
      ),
    );
  }

  Widget _githubButton(AppLocalizations l10n) {
    return Semantics(
      button: true,
      label: l10n.githubLink,
      hint: l10n.githubLinkHint,
      child: Material(
        color: AppPalette.surfaceStrong,
        shape: const StadiumBorder(
          side: BorderSide(color: AppPalette.buttonBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(
            launchUrl(
              Uri.parse(_githubUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          customBorder: const StadiumBorder(),
          child: const SizedBox(
            width: AppPalette.minTouchTarget,
            height: AppPalette.minTouchTarget,
            child: Center(
              child: Icon(
                SimpleIcons.github,
                size: 18,
                color: AppPalette.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuButton(AppLocalizations l10n) {
    final bool active = _open == _OpenMenu.actions;
    final Color foreground = active
        ? const Color(0xFF1B1B1B)
        : AppPalette.textPrimary;
    return Semantics(
      button: true,
      label: active ? l10n.navMenuCloseHint : l10n.navMenuOpenHint,
      child: Material(
        color: active ? AppPalette.accent : AppPalette.surfaceStrong,
        shape: const StadiumBorder(
          side: BorderSide(color: AppPalette.buttonBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(
            () => _open = active ? _OpenMenu.none : _OpenMenu.actions,
          ),
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppPalette.minTouchTarget,
              minHeight: AppPalette.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppPalette.spaceMd,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    active ? Icons.close : Icons.menu,
                    size: 18,
                    color: foreground,
                  ),
                  const SizedBox(width: AppPalette.spaceXs),
                  Text(
                    l10n.navMenuLabel,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageButton(AppLocalizations l10n) {
    final bool active = _open == _OpenMenu.language;
    final Color foreground = active
        ? const Color(0xFF1B1B1B)
        : AppPalette.textPrimary;
    // A font icon keeps the button recognisable no matter which language is
    // currently selected.
    return Semantics(
      button: true,
      label: l10n.languageLabel,
      hint: active ? l10n.languageMenuCloseHint : l10n.languageMenuOpenHint,
      child: Material(
        color: active ? AppPalette.accent : AppPalette.surfaceStrong,
        shape: const StadiumBorder(
          side: BorderSide(color: AppPalette.buttonBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(
            () => _open = active ? _OpenMenu.none : _OpenMenu.language,
          ),
          customBorder: const StadiumBorder(),
          child: SizedBox(
            width: AppPalette.minTouchTarget,
            height: AppPalette.minTouchTarget,
            child: Center(
              child: Icon(Icons.language, size: 18, color: foreground),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageOptions(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _languageOption(
          label: l10n.languageSystem,
          selected: widget.locale == null,
          onTap: () => _chooseLanguage(null),
        ),
        _languageOption(
          label: l10n.languageEnglish,
          selected: widget.locale?.languageCode == 'en',
          onTap: () => _chooseLanguage(const Locale('en')),
        ),
        _languageOption(
          label: l10n.languageChinese,
          selected: widget.locale?.languageCode == 'zh',
          onTap: () => _chooseLanguage(const Locale('zh')),
        ),
      ],
    );
  }

  Widget _languageOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final Color foreground = selected
        ? AppPalette.accent
        : AppPalette.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppPalette.spaceXs),
      child: Material(
        color: selected ? AppPalette.surfaceStrong : const Color(0x00000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: AppPalette.minTouchTarget,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppPalette.spaceSm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check, size: 16, color: AppPalette.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuPanel(Widget child, {double padding = AppPalette.panelPadding}) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppPalette.buttonSurface,
        borderRadius: BorderRadius.circular(AppPalette.panelRadius),
        border: Border.all(color: AppPalette.buttonBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(child: child),
    );
  }
}
