import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../session.dart';

class StatsBoard extends StatelessWidget {
  const StatsBoard({super.key, required this.session, this.width = 220});

  final CubeSession session;

  /// Panel width comes from the layout; the default matches the old fixed
  /// size for callers that use this widget standalone.
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (BuildContext context, Widget? _) {
        final List<Duration> recent = session.records.reversed.take(5).toList();
        return SizedBox(
          width: width,
          child: Panel(
            title: l10n.statsPanelTitle,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _row(l10n.statsTotalSolves, '${session.totalSolves}'),
                _row(l10n.statsBestTime, formatDurationOrDash(session.best)),
                _row(l10n.statsWorstTime, formatDurationOrDash(session.worst)),
                _row(
                  l10n.statsAverageOf5,
                  formatDurationOrDash(session.averageOf5),
                ),
                _row(
                  l10n.statsAverageOf12,
                  formatDurationOrDash(session.averageOf12),
                ),
                if (recent.isNotEmpty) ...<Widget>[
                  const Divider(height: 20, color: AppPalette.border),
                  Text(l10n.statsRecent, style: AppPalette.panelTitle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final Duration record in recent)
                        _chip(formatDuration(record)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppPalette.statLabel,
            ),
          ),
          const SizedBox(width: AppPalette.spaceSm),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppPalette.statValue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppPalette.surfaceStrong,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppPalette.statLabel.copyWith(color: AppPalette.textPrimary),
      ),
    );
  }
}
