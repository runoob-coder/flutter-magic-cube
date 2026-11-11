import 'package:magic_cube/magic_cube.dart';
import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../session.dart';

/// How the same set of actions is presented at a given screen size.
enum ActionBarVariant {
  /// All actions in a wrapping row (the original behaviour).
  wrap,

  /// Frequent actions, always visible on the first screen.
  primary,

  /// Restore / view / appearance actions.
  secondary,

  /// All actions in a single, full-width column (compact-screen menu).
  menu,
}

/// Groups keep `primary` + `secondary` a partition of all eight actions.
enum _ActionGroup { core, restore, view }

typedef _ActionSpec = ({
  String label,
  IconData icon,
  bool highlighted,
  _ActionGroup group,
  VoidCallback? onTap,
});

class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.controller,
    required this.session,
    required this.autoRotate,
    required this.onAutoRotateChanged,
    required this.onCycleTheme,
    required this.showLogo,
    required this.onToggleLogo,
    this.variant = ActionBarVariant.wrap,
  });

  final MagicCubeController controller;
  final CubeSession session;
  final bool autoRotate;
  final ValueChanged<bool> onAutoRotateChanged;
  final VoidCallback onCycleTheme;

  final bool showLogo;
  final VoidCallback onToggleLogo;

  final ActionBarVariant variant;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      // Listen to both: the scrambling label depends on session state,
      // undo availability on controller state (direct scramble() never
      // notifies the session).
      listenable: Listenable.merge(<Listenable>[controller, session]),
      builder: (BuildContext context, Widget? _) {
        final bool scrambling = session.phase == SessionPhase.scrambling;
        // moveCount avoids copying the whole history on every animation
        // frame.
        final bool canUndo = controller.moveCount > 0;

        // One definition for every layout; variants only filter / arrange it.
        final List<_ActionSpec> actions = <_ActionSpec>[
          (
            label: scrambling ? l10n.actionScrambling : l10n.actionScramble,
            icon: Icons.shuffle,
            highlighted: false,
            group: _ActionGroup.core,
            onTap: scrambling ? null : () => controller.scramble(length: 20),
          ),
          (
            label: l10n.actionUndo,
            icon: Icons.undo,
            highlighted: false,
            group: _ActionGroup.core,
            onTap: canUndo ? () => controller.undo() : null,
          ),
          (
            label: l10n.actionUndoAll,
            icon: Icons.history,
            highlighted: false,
            group: _ActionGroup.restore,
            onTap: canUndo
                ? () => controller.undoAll(
                    duration: const Duration(milliseconds: 110),
                  )
                : null,
          ),
          (
            label: l10n.actionResetCube,
            icon: Icons.clear,
            highlighted: false,
            group: _ActionGroup.core,
            onTap: () {
              controller.reset();
              session.abort();
            },
          ),
          (
            label: l10n.actionResetView,
            icon: Icons.filter_center_focus,
            highlighted: false,
            group: _ActionGroup.view,
            onTap: () => controller.resetView(),
          ),
          (
            label: autoRotate
                ? l10n.actionStopRotation
                : l10n.actionAutoRotation,
            icon: Icons.threed_rotation,
            highlighted: autoRotate,
            group: _ActionGroup.view,
            onTap: () => onAutoRotateChanged(!autoRotate),
          ),
          (
            label: showLogo ? l10n.actionHideLogo : l10n.actionShowLogo,
            icon: Icons.image,
            highlighted: showLogo,
            group: _ActionGroup.view,
            onTap: onToggleLogo,
          ),
          (
            label: l10n.actionTheme,
            icon: Icons.palette,
            highlighted: false,
            group: _ActionGroup.view,
            onTap: onCycleTheme,
          ),
        ];

        final bool showAll =
            variant == ActionBarVariant.wrap ||
            variant == ActionBarVariant.menu;
        // primary / secondary partition all eight actions with no overlap:
        // the header keeps the three core actions, the content region gets
        // step-by-step restore plus all view / appearance controls.
        final Set<_ActionGroup> groups = variant == ActionBarVariant.primary
            ? <_ActionGroup>{_ActionGroup.core}
            : <_ActionGroup>{_ActionGroup.restore, _ActionGroup.view};
        final Iterable<_ActionSpec> shown = showAll
            ? actions
            : actions.where(
                (_ActionSpec action) => groups.contains(action.group),
              );

        if (variant == ActionBarVariant.menu) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final _ActionSpec action in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppPalette.spaceSm),
                  child: _button(action, expanded: true),
                ),
            ],
          );
        }
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: AppPalette.spaceSm,
          runSpacing: AppPalette.spaceSm,
          children: <Widget>[
            for (final _ActionSpec action in shown) _button(action),
          ],
        );
      },
    );
  }

  Widget _button(_ActionSpec action, {bool expanded = false}) {
    return AppButton(
      label: action.label,
      icon: action.icon,
      highlighted: action.highlighted,
      onTap: action.onTap,
      expanded: expanded,
    );
  }
}
