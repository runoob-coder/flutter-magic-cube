import 'package:magic_cube/magic_cube.dart';
import 'package:magic_cube_example/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';

class MoveControls extends StatefulWidget {
  const MoveControls({super.key, required this.controller});

  final MagicCubeController controller;

  @override
  State<MoveControls> createState() => _MoveControlsState();
}

class _MoveControlsState extends State<MoveControls> {
  static const List<String> _faceMoves = <String>[
    'U',
    "U'",
    'U2',
    'D',
    "D'",
    'D2',
    'L',
    "L'",
    'L2',
    'R',
    "R'",
    'R2',
    'F',
    "F'",
    'F2',
    'B',
    "B'",
    'B2',
  ];

  static const List<String> _sliceMoves = <String>[
    'M',
    "M'",
    'E',
    "E'",
    'S',
    "S'",
    'x',
    "x'",
    'y',
    "y'",
    'z',
    "z'",
  ];

  final TextEditingController _editor = TextEditingController();
  bool _hasError = false;

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _applyToken(String token) {
    widget.controller.applyMove(CubeMove.parse(token));
  }

  void _applySequence() {
    final String sequence = _editor.text.trim();
    if (sequence.isEmpty) return;
    try {
      final List<CubeMove> moves = CubeMove.parseSequence(sequence);
      setState(() => _hasError = false);
      widget.controller.applyMoves(moves);
    } on FormatException {
      // Store only the flag, so a locale change rebuilds the message.
      setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Panel(
      title: l10n.movesPanelTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: AppPalette.spaceSm,
            runSpacing: AppPalette.spaceSm,
            children: <Widget>[
              for (final String token in _faceMoves)
                AppButton(
                  label: token,
                  compact: true,
                  onTap: () => _applyToken(token),
                ),
            ],
          ),
          const SizedBox(height: AppPalette.spaceSm),
          Wrap(
            spacing: AppPalette.spaceSm,
            runSpacing: AppPalette.spaceSm,
            children: <Widget>[
              for (final String token in _sliceMoves)
                AppButton(
                  label: token,
                  compact: true,
                  onTap: () => _applyToken(token),
                ),
            ],
          ),
          const SizedBox(height: AppPalette.spaceMd),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // A 320-360px phone cannot fit the field and the Run button in
              // one row without truncating the algorithm; stack them instead.
              final bool narrow = constraints.maxWidth < 360;
              final Widget field = TextField(
                controller: _editor,
                style: AppPalette.statValue,
                decoration: InputDecoration(
                  hintText: l10n.movesHint,
                  hintStyle: AppPalette.statLabel,
                  filled: true,
                  fillColor: AppPalette.surfaceStrong,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _applySequence(),
              );
              final Widget run = AppButton(
                label: l10n.movesRun,
                highlighted: true,
                expanded: narrow,
                onTap: _applySequence,
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    field,
                    const SizedBox(height: AppPalette.spaceSm),
                    run,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: field),
                  const SizedBox(width: AppPalette.spaceSm),
                  run,
                ],
              );
            },
          ),
          if (_hasError) ...<Widget>[
            const SizedBox(height: AppPalette.spaceXs),
            Text(
              l10n.movesError,
              style: AppPalette.statLabel.copyWith(color: AppPalette.accent),
            ),
          ],
        ],
      ),
    );
  }
}
