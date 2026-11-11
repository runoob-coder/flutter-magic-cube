import 'package:magic_cube/magic_cube.dart';
import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';

/// Values change only when a move commits, so cache the subtree instead of
/// rebuilding on every controller notification during animation.
class ProgressBoard extends StatefulWidget {
  const ProgressBoard({super.key, required this.controller, this.width = 220});

  final MagicCubeController controller;

  /// Panel width comes from the layout; it participates in the cache key
  /// so a resize never reuses a subtree built for the old width.
  final double width;

  @override
  State<ProgressBoard> createState() => _ProgressBoardState();
}

class _ProgressBoardState extends State<ProgressBoard> {
  Widget? _cached;
  int _faces = -1;
  int _moves = -1;
  Locale? _locale;
  double _width = -1;

  @override
  Widget build(BuildContext context) {
    // localeOf registers an InheritedWidget dependency so a system locale
    // change invalidates the cached panel without controller events.
    final Locale locale = Localizations.localeOf(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final int faces = widget.controller.solvedFaceCount;
        final int moves = widget.controller.moveCount;
        if (_cached != null &&
            faces == _faces &&
            moves == _moves &&
            locale == _locale &&
            widget.width == _width) {
          return _cached!;
        }
        _faces = faces;
        _moves = moves;
        _locale = locale;
        _width = widget.width;
        return _cached = _panel(l10n, faces, moves);
      },
    );
  }

  Widget _panel(AppLocalizations l10n, int faces, int moves) {
    // Notation needs the cube's size; higher orders otherwise print ?'.
    final int size = widget.controller.state.size;
    final List<String> recent = widget.controller.history.reversed
        .take(8)
        .map((CubeMove move) => move.notation(size: size))
        .toList();
    return SizedBox(
      width: widget.width,
      child: Panel(
        title: l10n.progressPanelTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(l10n.progressSolvedFaces, style: AppPalette.statLabel),
                const Spacer(),
                Text('$faces / 6', style: AppPalette.statValue),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: faces / 6,
                minHeight: 6,
                backgroundColor: AppPalette.surfaceStrong,
                valueColor: AlwaysStoppedAnimation<Color>(
                  faces == 6 ? AppPalette.accent : AppPalette.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Text(l10n.progressMoveCount, style: AppPalette.statLabel),
                const Spacer(),
                Text('$moves', style: AppPalette.statValue),
              ],
            ),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              Text(l10n.progressHint, style: AppPalette.statLabel)
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String token in recent) _chip(token),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String token) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppPalette.surfaceStrong,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(token, style: AppPalette.statValue.copyWith(fontSize: 13)),
    );
  }
}
