import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../session.dart';

class TimerHeader extends StatelessWidget {
  const TimerHeader({super.key, required this.session, this.fontSize = 54});

  final CubeSession session;

  /// Scaled per breakpoint; the default keeps the original size for
  /// callers that pump this widget on its own.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (BuildContext context, Widget? _) {
        final bool finished = session.phase == SessionPhase.finished;
        final Color color = finished
            ? AppPalette.accent
            : AppPalette.textPrimary;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              formatDuration(session.elapsed),
              style: AppPalette.timerTextFor(fontSize).copyWith(color: color),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText(l10n, session),
              style: AppPalette.statusText.copyWith(
                color: finished ? AppPalette.accent : AppPalette.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Keep localized text in the view layer; the model stores only the phase.
String _statusText(AppLocalizations l10n, CubeSession session) {
  return switch (session.phase) {
    SessionPhase.idle => l10n.statusIdle,
    SessionPhase.scrambling => l10n.statusScrambling,
    SessionPhase.solving => l10n.statusSolving,
    SessionPhase.finished =>
      session.isBestTime ? l10n.statusBestTime : l10n.statusComplete,
  };
}
